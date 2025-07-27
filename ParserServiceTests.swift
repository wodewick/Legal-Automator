//
//  ParserServiceTests.swift
//  Legal AutomatorTests
//
//  Verifies that `ParserService.tokenize(_:)` produces the correct
//  `TemplateElement` tree from raw template text.
//

import XCTest
@testable import Legal_Automator   // adjust module name if different

final class ParserServiceUnitTests: XCTestCase {

    private let parser = ParserService()

    // ---------------------------------------------------------------------
    // Helper
    // ---------------------------------------------------------------------
    private func parse(_ template: String) throws -> [TemplateElement] {
        try parser.tokenize(template)
    }

    // ---------------------------------------------------------------------
    // Variable parsing
    // ---------------------------------------------------------------------
    func testVariableParsing() throws {
        let template = "Hello {{client_name}}."
        let elements = try parse(template)

        XCTAssertEqual(elements.count, 3)

        guard case .plainText(_, "Hello ")           = elements[0],
              case .variable(_, "client_name", _, _) = elements[1],
              case .plainText(_, ".")                = elements[2] else {
            return XCTFail("Element sequence mismatch")
        }
    }

    // ---------------------------------------------------------------------
    // Nested conditionals + repeat
    // ---------------------------------------------------------------------
    func testNestedConditionalParsing() throws {
        let template = """
        [[IF is_company]]
        ACN: {{acn}}
        [[IF has_directors]]
        [[REPEAT FOR directors]]
        Dir: {{director_name}}
        [[END REPEAT]]
        [[END IF]]
        [[END IF]]
        """

        let elements = try parse(template)
        XCTAssertEqual(elements.count, 1)

        guard case .conditional(_, "is_company", _, let inner) = elements.first else {
            return XCTFail("Missing top-level conditional")
        }
        XCTAssertEqual(inner.count, 3)

        guard case .conditional(_, "has_directors", _, let deeper) = inner[2],
              case .repeatingGroup(_, "directors", _, let templateEls) = deeper[0],
              case .variable(_, "director_name", _, _) = templateEls[0] else {
            return XCTFail("Nested structure mismatch")
        }
    }

    // ---------------------------------------------------------------------
    // Repeat block
    // ---------------------------------------------------------------------
    func testRepeatBlockParsing() throws {
        let template = """
        Directors:
        [[REPEAT FOR directors]]
        - {{name}}
        [[END REPEAT]]
        """

        let elements = try parse(template)
        XCTAssertEqual(elements.count, 2)

        guard case .plainText                     = elements[0],
              case .repeatingGroup(_, "directors", _, let tmpl) = elements[1],
              case .variable(_, "name", _, _)     = tmpl.first else {
            return XCTFail("Repeating group parsed incorrectly")
        }
    }

    // ---------------------------------------------------------------------
    // Invalid syntax
    // ---------------------------------------------------------------------
    func testInvalidTemplateThrows() {
        let template = """
        [[IF something]]
        Missing END IF tag
        """
        XCTAssertThrowsError(try parse(template)) { error in
            guard case ParserError.invalidTemplate = error else {
                return XCTFail("Wrong error type")
            }
        }
    }
}
