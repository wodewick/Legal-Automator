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

    private func applyReplacements(_ xml: String,
                                   answers: [String: Any]) -> String {
        var out = xml
        out = replaceVariables(in: out, answers: answers)
        out = processConditionals(in: out, answers: answers)
        out = processRepeats(in: out, answers: answers)
        return out
    }

    /// Replaces {{variable}} placeholders with answer values.
    private func replaceVariables(in xml: String,
                                  answers: [String: Any]) -> String {
        let rx = try! NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#)
        var result = xml
        let matches = rx.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            .reversed()  // Replace back‑to‑front to keep ranges stable

        for m in matches {
            let name = (xml as NSString).substring(with: m.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            let value = answers[name].map { String(describing: $0) } ?? ""
            let escaped = escapeXML(value)
            result.replaceSubrange(
                Range(m.range, in: result)!,
                with: escaped
            )
        }
        return result
    }

    /// Handles [[IF var]] … [[END IF]] blocks.
    private func processConditionals(in xml: String,
                                     answers: [String: Any]) -> String {
        // Placeholder MVP: remove tags but do not drop blocks.
        // TODO: implement full true/false pruning.
        let ifOpen = try! NSRegularExpression(pattern: #"\[\[IF[^\]]+\]\]"#)
        let ifClose = try! NSRegularExpression(pattern: #"\[\[END\s+IF\]\]"#)
        var out = ifOpen.stringByReplacingMatches(in: xml, range: NSRange(xml.startIndex..., in: xml), withTemplate: "")
        out = ifClose.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        return out
    }

    /// Handles [[REPEAT FOR group]] … [[END REPEAT]] blocks.
    private func processRepeats(in xml: String,
                                answers: [String: Any]) -> String {
        // Placeholder MVP: strip repeat tags but keep single body.
        let repOpen = try! NSRegularExpression(pattern: #"\[\[REPEAT[^\]]+\]\]"#)
        let repClose = try! NSRegularExpression(pattern: #"\[\[END\s+REPEAT\]\]"#)
        var out = repOpen.stringByReplacingMatches(in: xml, range: NSRange(xml.startIndex..., in: xml), withTemplate: "")
        out = repClose.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
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
