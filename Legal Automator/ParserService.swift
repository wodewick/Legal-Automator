//
//  ParserService.swift
//
//
//  Created by Rodney S. on 27 July 2025.
//  Parses a .docx template into a nested [TemplateElement] tree.
//

import Foundation
import ZIPFoundation

// MARK: - Template model ----------------------------------------------------

enum TemplateElement: Identifiable, Hashable {

    case plainText(id: UUID, content: String)
    case variable(id: UUID, name: String, label: String?, hint: String?)
    case conditional(id: UUID, name: String, label: String?, elements: [TemplateElement])
    case repeatingGroup(id: UUID, group: String, label: String?, templateElements: [TemplateElement])

    var id: UUID {
        switch self {
        case .plainText(let id, _),
             .variable(let id, _, _, _),
             .conditional(let id, _, _, _),
             .repeatingGroup(let id, _, _, _):
            return id
        }
    }
}

// MARK: - Service errors ----------------------------------------------------

enum ParserError: Error, LocalizedError {
    case notADocx
    case missingDocumentXML
    case unreadableXML
    case invalidTemplate(reason: String)

    var errorDescription: String? {
        switch self {
        case .notADocx:
            return "The selected file is not a valid .docx archive."
        case .missingDocumentXML:
            return "The template is missing word/document.xml."
        case .unreadableXML:
            return "Unable to read the XML content of the document."
        case .invalidTemplate(let reason):
            return "Template syntax error: \(reason)."
        }
    }
}

// MARK: - Parser service ----------------------------------------------------

final class ParserService {

    // Public API ------------------------------------------------------------

    /// Parses the provided .docx template and returns a nested element tree.
    func parse(templateURL: URL) throws -> [TemplateElement] {

        // 1  Extract WordprocessingML
        let xmlString = try extractXML(from: templateURL)

        // 2  Collect contiguous text from all <w:t> nodes
        let documentText = try WordTextCollector.collectText(fromXML: xmlString)

        // 3  Tokenise into a nested tree
        return try tokenize(documentText)
    }

    // Private helpers -------------------------------------------------------

    private func extractXML(from url: URL) throws -> String {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ParserError.notADocx
        }
        guard let entry = archive["word/document.xml"] else {
            throw ParserError.missingDocumentXML
        }

        var xmlData = Data()
        _ = try archive.extract(entry) { xmlData.append($0) }

        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            throw ParserError.unreadableXML
        }
        return xmlString
    }

    // ----------------------------------------------------------------------

    /// Builds a nested [TemplateElement] tree from raw document text.
    private func tokenize(_ text: String) throws -> [TemplateElement] {

        // Regex patterns ----------------------------------------------------
        let variableRX  = try NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#)
        let ifOpenRX    = try NSRegularExpression(pattern: #"\[\[IF\s+([^\]]+)\]\]"#)
        let ifCloseRX   = try NSRegularExpression(pattern: #"\[\[END\s+IF\]\]"#)
        let repOpenRX   = try NSRegularExpression(pattern: #"\[\[REPEAT\s+FOR\s+([^\]]+)\]\]"#)
        let repCloseRX  = try NSRegularExpression(pattern: #"\[\[END\s+REPEAT\]\]"#)

        // Helpers -----------------------------------------------------------
        struct StackFrame {
            var elements: [TemplateElement] = []
            var context: Context
            enum Context { case root, conditional(name: String, label: String?), repeating(group: String, label: String?) }
        }

        var stack: [StackFrame] = [StackFrame(context: .root)]
        var cursor = text.startIndex

        // Utility that returns the first match among a set of regexes
        func nextMatch() -> (NSTextCheckingResult, NSRegularExpression)? {
            var best: (NSTextCheckingResult, NSRegularExpression)?
            let regexes = [variableRX, ifOpenRX, ifCloseRX, repOpenRX, repCloseRX]

            for rx in regexes {
                if let m = rx.firstMatch(in: text, range: NSRange(cursor..<text.endIndex, in: text)),
                   m.range.location != NSNotFound,
                   let r = Range(m.range, in: text) {

                    if best == nil || r.lowerBound < Range(best!.0.range, in: text)!.lowerBound {
                        best = (m, rx)
                    }
                }
            }
            return best
        }

        // Main walk ---------------------------------------------------------
        while cursor < text.endIndex {
            guard let (match, rx) = nextMatch(),
                  let range = Range(match.range, in: text) else {

                // No further tags
                let remainder = text[cursor...]
                appendPlainText(String(remainder), to: &stack[stack.count - 1].elements)
                break
            }

            // Emit any leading literal text
            if cursor < range.lowerBound {
                let literal = text[cursor..<range.lowerBound]
                appendPlainText(String(literal), to: &stack[stack.count - 1].elements)
            }

            // Dispatch based on which pattern matched
            switch rx {
            case variableRX:
                let body = (text as NSString).substring(with: match.range(at: 1))
                stack[stack.count - 1].elements.append(parseVariable(body))

            case ifOpenRX:
                let body = (text as NSString).substring(with: match.range(at: 1))
                let (name, label) = parseNameAndLabel(body)
                // Push new frame
                stack.append(StackFrame(context: .conditional(name: name, label: label)))

            case repOpenRX:
                let body = (text as NSString).substring(with: match.range(at: 1))
                let (group, label) = parseNameAndLabel(body)
                stack.append(StackFrame(context: .repeating(group: group, label: label)))

            case ifCloseRX:
                try closeContext(expect: .conditional, stack: &stack)

            case repCloseRX:
                try closeContext(expect: .repeating, stack: &stack)

            default:
                break
            }

            cursor = range.upperBound
        }

        guard stack.count == 1 else {
            throw ParserError.invalidTemplate(reason: "Unmatched opening tag")
        }

        return stack[0].elements
    }

    // MARK: - Token helpers -------------------------------------------------

    private func appendPlainText(_ text: String, to array: inout [TemplateElement]) {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        array.append(.plainText(id: UUID(), content: text))
    }

    private func parseVariable(_ body: String) -> TemplateElement {
        let parts = body.components(separatedBy: ",")
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        var label: String?
        var hint: String?
        for part in parts.dropFirst() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("label:") {
                label = trimmed.replacingOccurrences(of: "label:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("hint:") {
                hint = trimmed.replacingOccurrences(of: "hint:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return .variable(id: UUID(), name: name, label: label, hint: hint)
    }

    private func parseNameAndLabel(_ body: String) -> (String, String?) {
        let parts = body.components(separatedBy: ",")
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        let label = parts.dropFirst()
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("label:") })?
            .replacingOccurrences(of: "label:", with: "")
            .trimmingCharacters(in: .whitespaces)
        return (name, label)
    }

    private func closeContext(expect expected: StackFrame.Context, stack: inout [StackFrame]) throws {
        guard stack.count > 1 else {
            throw ParserError.invalidTemplate(reason: "Unexpected closing tag")
        }
        let finished = stack.removeLast()
        let parentIndex = stack.count - 1

        switch (finished.context, expected) {

        case (.conditional(let name, let label), .conditional):
            let element = TemplateElement.conditional(id: UUID(), name: name, label: label, elements: finished.elements)
            stack[parentIndex].elements.append(element)

        case (.repeating(let group, let label), .repeating):
            let element = TemplateElement.repeatingGroup(id: UUID(), group: group, label: label, templateElements: finished.elements)
            stack[parentIndex].elements.append(element)

        default:
            throw ParserError.invalidTemplate(reason: "Mismatched closing tag")
        }
    }
}

// MARK: - Word text collector ----------------------------------------------

private final class WordTextCollector: NSObject, XMLParserDelegate {

    private var buffer: String = ""

    static func collectText(fromXML xml: String) throws -> String {
        let parser = XMLParser(data: Data(xml.utf8))
        let collector = WordTextCollector()
        parser.delegate = collector
        guard parser.parse() else {
            throw ParserError.unreadableXML
        }
        return collector.buffer
    }

    // We only care about text inside <w:t> elements ------------------------
    private var isInTextNode = false

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {

        if elementName == "w:t" { isInTextNode = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInTextNode { buffer.append(string) }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {

        if elementName == "w:t" { isInTextNode = false }
    }
}
