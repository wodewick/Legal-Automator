//
//  GeneratorService.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//  MVP implementation – copies the template, performs in‑memory XML transforms,
//  and writes the updated document back into the new .docx archive.
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
    ///   UUID‑named file inside it) or a full file URL ending in “.docx”.
    /// - Returns: The final document's URL.
    func generate(templateURL: URL,
                  answers: [String: Any],
                  destinationURL: URL) throws -> URL {

        // ------------------------------------------------------------------
        //  1. Decide final output path
        // ------------------------------------------------------------------
        let outputURL: URL
        if destinationURL.pathExtension.lowercased() == "docx" {
            outputURL = destinationURL
        } else {
            outputURL = destinationURL.appendingPathComponent(
                UUID().uuidString + ".docx"
            )
        }

        // Ensure parent directory exists
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // ------------------------------------------------------------------
        //  2. Copy template -> outputURL
        // ------------------------------------------------------------------
        // Overwrite if the file exists
        _ = try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.copyItem(at: templateURL, to: outputURL)

        // ------------------------------------------------------------------
        //  3. Open copied archive for update
        // ------------------------------------------------------------------
        let archive = try Archive(url: outputURL, accessMode: .update)

        guard let entry = archive["word/document.xml"] else {
            throw GeneratorError.missingDocumentXML
        }

        // Extract XML to memory
        var xmlData = Data()
        _ = try archive.extract(entry) { xmlData.append($0) }
        guard var xmlString = String(data: xmlData, encoding: .utf8) else {
            throw GeneratorError.readWriteFailure
        }

        // ------------------------------------------------------------------
        //  4. Apply replacements
        // ------------------------------------------------------------------
        xmlString = applyReplacements(xmlString, answers: answers)

        // ------------------------------------------------------------------
        //  5. Write back
        // ------------------------------------------------------------------
        try archive.remove(entry)

        let finalData = Data(xmlString.utf8)
        try archive.addEntry(
            with: "word/document.xml",
            type: .file,
            uncompressedSize: UInt32(finalData.count),
            compressionMethod: .deflate,
            provider: { position, size -> Data in
                return finalData.subdata(in: Int(position)..<Int(position + size))
            })

        return outputURL
    }

    // MARK: - Replacement pipeline -----------------------------------------
    //
    // The pipeline order is Variable ➜ Conditional ➜ Repeat.  Each stage may
    // call `applyReplacements` recursively to ensure nested constructs are
    // resolved with the appropriate answer scope.
    private func applyReplacements(_ xml: String,
                                   answers: [String: Any]) -> String {
        var out = xml
        out = replaceVariables(in: out, answers: answers)
        out = processConditionals(in: out, answers: answers)
        out = processRepeats(in: out, answers: answers)
        return out
    }

    /// Replaces {{variable}} placeholders with answer values.
    /// Values are converted to strings via `String(describing:)` and XML‑escaped.
    private func replaceVariables(in xml: String,
                                  answers: [String: Any]) -> String {

        let rx = try! NSRegularExpression(pattern: #"\{\{\s*([^}\s]+)\s*\}\}"#)
        var result = xml

        // Iterate from the end of the document forward so that earlier index
        // ranges remain valid after replacements.
        for match in rx.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).reversed() {

            let name = (xml as NSString).substring(with: match.range(at: 1))
            let raw  = answers[name].map { String(describing: $0) } ?? ""
            let escaped = escapeXML(raw)

            result.replaceSubrange(
                Range(match.range, in: result)!,
                with: escaped
            )
        }
        return result
    }

    /// Evaluates [[IF xyz]] … [[END IF]] blocks.
    /// The block is included **only** when `answers[xyz]` is truthy (`Bool == true`)
    /// or a non‑empty string / non‑zero number.
    private func processConditionals(in xml: String,
                                     answers: [String: Any]) -> String {

        let pattern = #"(?s)\[\[IF\s+([^\]]+)\]\](.*?)\[\[END\s+IF\]\]"#
        let rx = try! NSRegularExpression(pattern: pattern, options: [])

        var out = xml
        for match in rx.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).reversed() {

            let varName = (xml as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let body    = (xml as NSString).substring(with: match.range(at: 2))

            let value   = answers[varName]
            let isTrue: Bool = {
                switch value {
                case nil:                 return false
                case let b as Bool:       return b
                case let s as String:     return s.isEmpty == false
                case let n as NSNumber:   return n != 0
                default:                  return true   // non‑nil, non‑empty
                }
            }()

            let replacement = isTrue
                ? applyReplacements(body, answers: answers) // recurse so inner tags resolved
                : ""

            out.replaceSubrange(Range(match.range, in: out)!, with: replacement)
        }
        return out
    }

    /// Expands [[REPEAT FOR group]] … [[END REPEAT]] blocks.
    /// Expects `answers[group]` to be `[[String: Any]]`.
    private func processRepeats(in xml: String,
                                answers: [String: Any]) -> String {

        let pattern = #"(?s)\[\[REPEAT\s+FOR\s+([^\]]+)\]\](.*?)\[\[END\s+REPEAT\]\]"#
        let rx = try! NSRegularExpression(pattern: pattern, options: [])

        var out = xml
        for match in rx.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).reversed() {

            let groupName = (xml as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let body      = (xml as NSString).substring(with: match.range(at: 2))
            let rows      = answers[groupName] as? [[String: Any]] ?? []

            let rendered = rows.map { rowDict in
                applyReplacements(body, answers: rowDict)   // recursive processing
            }.joined()

            out.replaceSubrange(Range(match.range, in: out)!, with: rendered)
        }
        return out
    }

    // MARK: - Helpers -------------------------------------------------------

    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
