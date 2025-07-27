//
//  TemplateElement.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//



import Foundation


/// Canonical template model shared by ParserService, the UI, and (later)
/// GeneratorService.  This replaces the earlier flat model.
public enum TemplateElement: Identifiable, Hashable {

    /// Literal text that should appear in the questionnaire exactly as-is.
    case plainText(id: UUID = UUID(), content: String)

    /// A single‐value variable placeholder (e.g. {{ client_name }}).
    case variable(id: UUID = UUID(),
                  name: String,
                  label: String?,
                  hint: String?)

    /// A conditional block (originating from [[IF …]] … [[END IF]]).
    case conditional(id: UUID = UUID(),
                     name: String,
                     label: String?,
                     elements: [TemplateElement])

    /// A repeating group block (originating from [[REPEAT FOR …]] … [[END REPEAT]]).
    case repeatingGroup(id: UUID = UUID(),
                        group: String,
                        label: String?,
                        templateElements: [TemplateElement])

    // MARK: - Identity

    public var id: UUID {
        switch self {
        case .plainText(let id, _),
             .variable(let id, _, _, _),
             .conditional(let id, _, _, _),
             .repeatingGroup(let id, _, _, _):
            return id
        }
    }
}
