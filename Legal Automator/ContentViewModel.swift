//
//  ContentViewModel.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//

import Foundation
import SwiftUI
import AppKit

final class ContentViewModel: ObservableObject {
    // MARK: - Template state
    @Published var templateURL: URL? = nil
    @Published var elements: [TemplateElement] = []
    @Published var answers: [String: Any] = [:]

    // Surface simple user-visible errors
    @Published var errorMessage: String? = nil

    // For compatibility with existing views expecting `templateElements`
    var templateElements: [TemplateElement] { elements }

    init() {
        // Seed demo elements so the UI renders before a template is chosen
        self.elements = [
            .staticText(content: "Please complete the questionnaire below."),
            .textField(name: "client_name", label: "Client Name", hint: "Full legal name", type: .text),
            .textField(name: "matter_value", label: "Matter Value", hint: "e.g. 150000", type: .number),
            .textField(name: "review_date", label: "Review Date", hint: "YYYY-MM-DD", type: .text),
            .textField(name: "urgent", label: "Urgent?", hint: "true/false", type: .text),
            .textField(name: "category", label: "Category", hint: "Conveyancing / Wills / Litigation", type: .text),
            .repeatingGroup(name: "declarations", label: "Declarations", templateElements: [
                .textField(name: "decl1", label: "Declaration 1", hint: "", type: .text),
                .textField(name: "decl2", label: "Declaration 2", hint: "", type: .text)
            ])
        ]
    }

    // MARK: - Actions
    func selectTemplate() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["docx"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select a .docx template"
        if panel.runModal() == .OK, let url = panel.url {
            self.templateURL = url
            do {
                try loadTemplate(from: url)
            } catch {
                self.errorMessage = "Failed to load template: \(error.localizedDescription)"
            }
        }
    }

    func generateDocument() {
        // Placeholder generation logic; integrate your real merge pipeline here
        guard templateURL != nil else {
            errorMessage = "Please select a template before generating a document."
            return
        }
        // In a real implementation, perform the merge and write out a file.
        // For now, just indicate success.
        errorMessage = nil
    }

    // MARK: - Parsing (stub)
    private func loadTemplate(from url: URL) throws {
        // TODO: Parse `url` to populate `elements`.
        // This stub keeps the seeded elements. Replace with real parsing.
        // If parsing fails, throw an error.
    }
}
