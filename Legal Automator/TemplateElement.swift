//
//  TemplateElement.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//


import Foundation

/// Minimal model describing a single prompt/field in your template.
/// Expand this as your template format evolves.
struct TemplateElement: Identifiable, Hashable, Codable {
    enum Kind: String, Codable, CaseIterable {
        case text
        case number
        case date
        case toggle
        case picker
        case group
    }

    /// Use a stable id if your source format provides one.
    var id: UUID = UUID()

    /// Machine key used to store the answer.
    var key: String

    /// Human-readable label shown in the UI.
    var prompt: String

    /// Field type.
    var kind: Kind

    /// For choice fields.
    var options: [String]? = nil

    /// For grouped/repeating structures.
    var children: [TemplateElement]? = nil
}