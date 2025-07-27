//
//  ContentViewModel 2.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//


import Foundation
import SwiftUI

final class ContentViewModel: ObservableObject {

    /// Strongly typed template drives the view layer.
    @Published var elements: [TemplateElement] = []

    /// Very simple answer store to keep this example compiling.
    /// Replace with your real answer model/bindings as needed.
    @Published var answers: [String: String] = [:]

    init() {
        // Temporary seed so the app shows something at runtime.
        // Replace with your real loading/parsing logic.
        self.elements = [
            TemplateElement(key: "client_name", prompt: "Client Name", kind: .text),
            TemplateElement(key: "matter_value", prompt: "Matter Value", kind: .number),
            TemplateElement(key: "review_date", prompt: "Review Date", kind: .date),
            TemplateElement(key: "urgent", prompt: "Urgent?", kind: .toggle),
            TemplateElement(key: "category", prompt: "Category", kind: .picker, options: ["Conveyancing", "Wills", "Litigation"]),
            TemplateElement(
                key: "declarations",
                prompt: "Declarations",
                kind: .group,
                children: [
                    TemplateElement(key: "decl1", prompt: "Declaration 1", kind: .text),
                    TemplateElement(key: "decl2", prompt: "Declaration 2", kind: .text)
                ]
            )
        ]
    }

    // MARK: - Loading/parsing template
    // Implement your real template loader here and assign to `elements`.
    func loadTemplate(from url: URL) throws {
        // Parse file into [TemplateElement] and assign to `elements`.
        // Ensure you produce stable keys so answers line up with elements.
    }
}