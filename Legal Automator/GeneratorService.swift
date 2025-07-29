//
//  GeneratorService.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//  Generates a completed .docx by merging answers into the template.
//

import Foundation
import ZIPFoundation

// MARK: - Generator errors --------------------------------------------------

enum GeneratorError: LocalizedError {
    case missingDocumentXML
    case readWriteFailure
    case invalidAnswers(String)

    var errorDescription: String? {
        switch self {
        case .missingDocumentXML:
            return "The template is missing word/document.xml."
        case .readWriteFailure:
            return "Unable to update the document contents."
        case .invalidAnswers(let v):
            return "Invalid or missing answer for “\(v)”."
        }
    }
}

// MARK: - Service -----------------------------------------------------------

struct GeneratorService {

    /// Generates a completed .docx by merging `answers` into `templateURL`.
    /// - Parameter templateURL: The original template.
    /// - Parameter answers:     Dictionary keyed by variable / group name.
    /// - Parameter destinationURL: Either a **folder** (the method creates a
    ///   UUID-named file inside it) or a full file URL ending in “.docx”.
    /// - Returns: The final document's URL.
    func generate(templateURL: URL,
                  answers: [String: Any],
                  destinationURL: URL) throws -> URL {

        // Decide final output path
        let outputURL: URL = destinationURL.pathExtension.lowercased() == "docx"
            ? destinationURL
            : destinationURL.appendingPathComponent(UUID().uuidString + ".docx")

        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        // Copy template to output
        _ = try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.copyItem(at: templateURL, to: outputURL)

        // Open copied archive for update
        let archive = try Archive(url: outputURL, accessMode: .update)
        guard let entry = archive["word/document.xml"] else {
            throw GeneratorError.missingDocumentXML
        }

        // Extract XML
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        guard var xml = String(data: data, encoding: .utf8) else {
            throw GeneratorError.readWriteFailure
        }

        // Coalesce split text-runs
        xml = coalesceRuns(xml)

        // Apply replacements
        xml = applyReplacements(xml, answers: answers)

        // Write back
        try archive.remove(entry)
        let finalData = Data(xml.utf8)
        try archive.addEntry(with: "word/document.xml",
                             type: .file,
                             uncompressedSize: Int64(finalData.count),
                             compressionMethod: .deflate,
                             provider: { position, size in
                                 finalData.subdata(in: Int(position)..<Int(position + size))
                             })

        return outputURL
    }

    // MARK: - Replacement pipeline -----------------------------------------

    private func applyReplacements(_ xml: String,
                                   answers: [String: Any]) -> String {
        var out = xml
        out = replaceVariables(in: out, answers: answers)
        out = processConditionals(in: out, answers: answers)
        out = processRepeats(in: out, answers: answers)
        return out
    }

    // Variable replacement
    private func replaceVariables(in xml: String,
                                  answers: [String: Any]) -> String {
        let rx = try! NSRegularExpression(pattern: #"\{\{\s*([^}\s]+)\s*\}\}"#)
        var result = xml
        for match in rx.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).reversed() {
            let name = (xml as NSString).substring(with: match.range(at: 1))
            let val  = answers[name].map { String(describing: $0) } ?? ""
            let escaped = escapeXML(val)
            result.replaceSubrange(Range(match.range, in: result)!, with: escaped)
        }
        return result
    }

    // Conditional blocks
    private func processConditionals(in xml: String,
                                     answers: [String: Any]) -> String {
        let pattern = #"(?s)\[\[IF\s+([^\]]+)\]\](.*?)\[\[END\s+IF\]\]"#
        let rx = try! NSRegularExpression(pattern: pattern)
        var out = xml
        for match in rx.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).reversed() {
            let varName = (xml as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let body    = (xml as NSString).substring(with: match.range(at: 2))
            let val     = answers[varName]

            let include: Bool = {
                switch val {
                case let b as Bool:     return b
                case let s as String:   return !s.isEmpty
                case let n as NSNumber: return n != 0
                case nil:               return false
                default:                return true
                }
            }()

            let replacement = include ? applyReplacements(body, answers: answers) : ""
            out.replaceSubrange(Range(match.range, in: out)!, with: replacement)
        }
        return out
    }

    // Repeating blocks
    private func processRepeats(in xml: String,
                                answers: [String: Any]) -> String {
        let pattern = #"(?s)\[\[REPEAT\s+FOR\s+([^\]]+)\]\](.*?)\[\[END\s+REPEAT\]\]"#
        let rx = try! NSRegularExpression(pattern: pattern)
        var out = xml
        for match in rx.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).reversed() {
            let groupName = (xml as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let body      = (xml as NSString).substring(with: match.range(at: 2))
            let rows      = answers[groupName] as? [[String: Any]] ?? []

            let rendered = rows.map { row in
                applyReplacements(body, answers: row)
            }.joined()

            out.replaceSubrange(Range(match.range, in: out)!, with: rendered)
        }
        return out
    }

    // MARK: - Helpers -------------------------------------------------------

    /// Coalesces split runs so placeholders are contiguous.
    private func coalesceRuns(_ xml: String) -> String {
        let pattern = #"</w:t>\s*</w:r>\s*<w:r[^>]*>\s*<w:t[^>]*>"#
        let rx = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return rx.stringByReplacingMatches(in: xml,
                                           range: NSRange(xml.startIndex..., in: xml),
                                           withTemplate: "")
    }

    private func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'",  with: "&apos;")
    }
}
