//
//  GeneratorServiceTests.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//


//
//  GeneratorServiceTests.swift
//  Legal AutomatorTests
//
//  Verifies that GeneratorService correctly merges variables,
//  conditionals, and repeating blocks into a finished document.xml
//  inside a temporary .docx archive.
//

import XCTest
import ZIPFoundation
@testable import Legal_Automator   // adjust module name if different

final class GeneratorServiceTests: XCTestCase {

    // MARK: - Helpers ------------------------------------------------------

    /// Builds a minimal .docx in /tmp whose `word/document.xml` contains
    /// the provided `template` string.
    private func makeDocx(with template: String, file: StaticString = #file, line: UInt = #line) throws -> URL {

        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".docx")

        let templateXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>\(template)</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """

        let archive = try Archive(url: tmpURL, accessMode: .create)

        // [Content_Types].xml
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        let ctData = Data(contentTypes.utf8)
        try archive.addEntry(with: "[Content_Types].xml",
                             type: .file,
                             uncompressedSize: UInt32(ctData.count),
                             provider: { position, size in
                                 ctData.subdata(in: Int(position)..<Int(position + size))
                             })

        // _rels/.rels
        let rels = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        let relsData = Data(rels.utf8)
        try archive.addEntry(with: "_rels/.rels",
                             type: .file,
                             uncompressedSize: UInt32(relsData.count),
                             provider: { position, size in
                                 relsData.subdata(in: Int(position)..<Int(position + size))
                             })

        // word/document.xml
        let docData = Data(templateXML.utf8)
        try archive.addEntry(with: "word/document.xml",
                             type: .file,
                             uncompressedSize: UInt32(docData.count),
                             provider: { position, size in
                                 docData.subdata(in: Int(position)..<Int(position + size))
                             })

        return tmpURL
    }

    /// Extracts and returns the merged word/document.xml text for inspection.
    private func mergedXML(from docxURL: URL) throws -> String {
        let archive = try Archive(url: docxURL, accessMode: .read)
        guard let entry = archive["word/document.xml"] else {
            throw XCTSkip("document.xml missing")
        }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Tests --------------------------------------------------------

    func testVariableReplacement() throws {
        let tpl = try makeDocx(with: "Hello {{name}}.")
        let answers: [String: Any] = ["name": "Alice"]

        let out = try GeneratorService().generate(templateURL: tpl,
                                                  answers: answers,
                                                  destinationURL: tpl.deletingLastPathComponent())

        let xml = try mergedXML(from: out)
        XCTAssertFalse(xml.contains("{{"), "Placeholder not replaced")
        XCTAssertTrue(xml.contains("Hello Alice."),
                      "Merged XML did not include substituted value")
    }

    func testConditionalTrue() throws {
        let tpl = try makeDocx(with: "[[IF show]]Yes[[END IF]]")
        let answers: [String: Any] = ["show": true]

        let out = try GeneratorService().generate(templateURL: tpl,
                                                  answers: answers,
                                                  destinationURL: tpl.deletingLastPathComponent())

        let xml = try mergedXML(from: out)
        XCTAssertTrue(xml.contains("Yes"))
    }

    func testConditionalFalse() throws {
        let tpl = try makeDocx(with: "[[IF show]]Hidden[[END IF]]")
        let answers: [String: Any] = ["show": false]

        let out = try GeneratorService().generate(templateURL: tpl,
                                                  answers: answers,
                                                  destinationURL: tpl.deletingLastPathComponent())

        let xml = try mergedXML(from: out)
        XCTAssertFalse(xml.contains("Hidden"))
    }

    func testRepeatExpansion() throws {
        let tplText = """
        [[REPEAT FOR items]]
        - {{item}}
        [[END REPEAT]]
        """
        let tpl = try makeDocx(with: tplText)
        let answers: [String: Any] = [
            "items": [
                ["item": "One"],
                ["item": "Two"]
            ]
        ]

        let out = try GeneratorService().generate(templateURL: tpl,
                                                  answers: answers,
                                                  destinationURL: tpl.deletingLastPathComponent())

        let xml = try mergedXML(from: out)

        // Helper closure to see if a plain string appears contiguously *or*
        // split across two w:t runs.
        func containsWord(_ word: String, in rawXML: String) -> Bool {
            // Matches <w:t>One</w:t> or O</w:t><w:t>ne
            let pattern = "<w:t[^>]*>\\s*\(word.prefix(1))[^<]*</w:t>(?:\\s*</w:r>\\s*<w:r[^>]*>\\s*<w:t[^>]*>)?\\s*\(word.dropFirst())\\s*</w:t>"
            return rawXML.range(of: pattern, options: .regularExpression) != nil
        }

        XCTAssertTrue(containsWord("One", in: xml), "Item 'One' missing")
        XCTAssertTrue(containsWord("Two", in: xml), "Item 'Two' missing")

        // Still keep the simple bullet‑count heuristic
        XCTAssertEqual(xml.components(separatedBy: "- ").count - 1, 2, "Expected two bullet points")
    }
}
