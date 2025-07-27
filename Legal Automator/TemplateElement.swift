//
//  TemplateElement.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//



import Foundation

/// The template model driving the questionnaire UI.
/// Cases include an `id` as the first associated value so that
/// pattern matching in views can ignore it with `_` while still
/// providing stable identity for `ForEach`.
enum TemplateElement: Identifiable {
    case textField(id: UUID = UUID(), name: String, label: String, hint: String = "", type: TextFieldType = .text)
    case conditional(id: UUID = UUID(), name: String, label: String, subElements: [TemplateElement])
    case repeatingGroup(id: UUID = UUID(), name: String, label: String, templateElements: [TemplateElement])
    case staticText(id: UUID = UUID(), content: String)

    enum TextFieldType: String, CaseIterable {
        case text
        case number
        case currency
    }

    var id: UUID {
        switch self {
        case .textField(let id, _, _, _, _): return id
        case .conditional(let id, _, _, _): return id
        case .repeatingGroup(let id, _, _, _): return id
        case .staticText(let id, _): return id
        }
    }
}
