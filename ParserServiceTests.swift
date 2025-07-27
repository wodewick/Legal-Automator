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
    
    /// Returns elements omitting `.plainText` whose text is only whitespace /
    /// newlines, so tests are not fragile to formatting.
    private func significant(_ elements: [TemplateElement]) -> [TemplateElement] {
        elements.filter {
            if case .plainText(_, let t) = $0 {
                return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
            return true
        }
    }

    /// Returns true if any element in the array is a `.variable` with the given name.
    private func containsVariable(_ name: String, in elements: [TemplateElement]) -> Bool {
        elements.contains { if case .variable(_, name, _, _) = $0 { return true }; return false }
    }

    // ---------------------------------------------------------------------
    // Variable parsing
    // ---------------------------------------------------------------------
    func testVariableParsing() throws {
        let template = "Hello {{client_name}}."
        let elements = try parse(template)
        let sig = significant(elements)
        XCTAssertEqual(sig.count, 3)

        guard case .plainText(_, "Hello ")           = sig[0],
              case .variable(_, "client_name", _, _) = sig[1],
              case .plainText(_, ".")                = sig[2] else {
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
        let sig = significant(elements)
        XCTAssertEqual(sig.count, 1)

        guard case .conditional(_, "is_company", _, let inner) = sig[0] else {
            return XCTFail("Missing top-level conditional")
        }
        let innerSig = significant(inner)

        // locate the 'has_directors' conditional inside innerSig
        guard let hasDir = innerSig.first(where: {
            if case .conditional(_, "has_directors", _, _) = $0 { return true }
            return false
        }),
        case .conditional(_, "has_directors", _, let deeper) = hasDir else {
            return XCTFail("Nested structure mismatch")
        }
        // Find the repeating group inside `deeper`
        let repeatElement = deeper.first { if case .repeatingGroup = $0 { return true } ; return false }
        guard case .repeatingGroup(_, "directors", _, let tmpl) = repeatElement else {
            return XCTFail("Repeating group not found")
        }
        let tmplSig = significant(tmpl)
        guard containsVariable("director_name", in: tmplSig) else {
            return XCTFail("Variable 'director_name' missing in template")
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
        let sig = significant(elements)

        // Locate the repeating group element
        guard let group = sig.first(where: {
            if case .repeatingGroup = $0 { return true }; return false
        }),
              case .repeatingGroup(_, "directors", _, let tmpl) = group else {
            return XCTFail("Repeating group parsed incorrectly")
        }
        let tmplSig = significant(tmpl)
        guard containsVariable("name", in: tmplSig) else {
            return XCTFail("Variable 'name' missing in template")
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
