//
//  ParserServiceTests.swift
//  Legal AutomatorTests
//
//  Created by Unit-Test Bot on 27 July 2025.
//

import XCTest
@testable import Legal_Automator   // adjust if your module name differs

/// Miniature XML fragments wrap the WordprocessingML text we care about.
/// We want just enough structure so that ParserService’s XMLParserDelegate
/// finds the `<w:t>` nodes.
private func wrap(_ body: String) -> String {
    return """
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
            <w:p><w:r><w:t>\(body)</w:t></w:r></w:p>
        </w:body>
    </w:document>
    """
}

final class ParserServiceTests: XCTestCase {

    private let parser = ParserService()

    // MARK: - Variables ----------------------------------------------------

    func testVariableParsing() throws {
        let xml = wrap("Hello {{client_name}}.")
        let elements = try parser.parse(templateXML: xml)   // helper overload below
        XCTAssertEqual(elements.count, 2)

        guard case .plainText(_, let txt1) = elements[0],
              case .variable(_, let name, _, _) = elements[1] else {
            XCTFail("Unexpected element sequence"); return
        }
        XCTAssertEqual(txt1, "Hello ")
        XCTAssertEqual(name, "client_name")
    }

    // MARK: - Nested conditionals ------------------------------------------

    func testNestedConditionalParsing() throws {
        let xml = wrap("""
            [[IF is_company]]
            ACN: {{acn}}
            [[IF has_directors]]
            [[REPEAT FOR directors]]
            Dir: {{director_name}}
            [[END REPEAT]]
            [[END IF]]
            [[END IF]]
            """)

        let elements = try parser.parse(templateXML: xml)

        XCTAssertEqual(elements.count, 1)
        guard case .conditional(_, "is_company", _, let inner) = elements[0],
              case .plainText = inner[0],
              case .variable(_, "acn", _, _) = inner[1],
              case .conditional(_, "has_directors", _, let deeper) = inner[2],
              case .repeatingGroup(_, "directors", _, let template) = deeper[0],
              case .variable(_, "director_name", _, _) = template[0] else {
            XCTFail("Structure mismatch"); return
        }
    }

    // MARK: - Repeat block --------------------------------------------------

    func testRepeatBlockParsing() throws {
        let xml = wrap("""
            Directors:
            [[REPEAT FOR directors]]
            - {{name}}
            [[END REPEAT]]
            """)
        let elements = try parser.parse(templateXML: xml)
        XCTAssertEqual(elements.count, 2)
        guard case .plainText(_, let heading) = elements[0],
              case .repeatingGroup(_, "directors", _, let template) = elements[1],
              case .variable(_, "name", _, _) = template.first else {
            XCTFail(); return
        }
        XCTAssertEqual(heading.trimmingCharacters(in: .whitespacesAndNewlines), "Directors:")
    }

    // MARK: - Invalid syntax -----------------------------------------------

    func testInvalidTemplateThrows() {
        let xml = wrap("""
            [[IF something]]
            Missing END IF tag
            """)
        XCTAssertThrowsError(try parser.parse(templateXML: xml)) { error in
            guard case ParserError.invalidTemplate = error else {
                XCTFail("Unexpected error type"); return
            }
        }
    }
}

// MARK: - Convenience overload ---------------------------------------------

private extension ParserService {
    /// Test-only helper that feeds raw XML instead of a .docx file.
    func parse(templateXML: String) throws -> [TemplateElement] {
        try tokenize(templateXML) // uses internal method via @testable import
    }
}
