//
//  ContentViewModel.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//  Updated: 04/09/2025 – separate busy state from error text, use allowedContentTypes
//  on NSSavePanel with fallback, and enforce .docx extension on saves.
//

import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Top-level view-model orchestrating template selection, parsing, and (later)
/// document generation.
final class ContentViewModel: ObservableObject {

    // MARK: Dependencies
    private let parser = ParserService()

    // MARK: Template state
    @Published var templateURL: URL?
    @Published private(set) var elements: [TemplateElement] = [
        .plainText(content: "Select a template to begin.")
    ]
    /// Answers keyed by variable / group name.  GeneratorService will consume
    /// this in Milestone 2.
    @Published var answers: [String: Any] = [:]

    // MARK: UI feedback
    /// Present only real errors to the operator. Do not overload with status text.
    @Published var errorMessage: String?
    /// Busy flag for long-running work (e.g., generation). Views can show a spinner.
    @Published var isGenerating: Bool = false

    /// Back-compat shim: some older views still reference `templateElements`.
    var templateElements: [TemplateElement] { elements }

    // MARK: User actions ----------------------------------------------------

    /// Show an Open dialog so the operator can choose a *.docx* template.
    func selectTemplate() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        } else {
            panel.allowedFileTypes = ["docx"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select a .docx template"

        if panel.runModal() == .OK, let url = panel.url {
            openTemplate(at: url)
        }
    }

    /// Merge `answers` into `templateURL` to produce an output document.
    @MainActor
    func generateDocument() {
        guard let tplURL = templateURL else {
            errorMessage = "Please select a template before generating a document."
            return
        }

        let panel = NSSavePanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        } else {
            panel.allowedFileTypes = ["docx"]
        }
        panel.nameFieldStringValue = "Merged-Document.docx"

        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }

        // Ensure the destination ends with .docx (handles no extension or a wrong one).
        let saveURL: URL = {
            let ext = chosenURL.pathExtension.lowercased()
            if ext.isEmpty {
                return chosenURL.appendingPathExtension("docx")
            } else if ext != "docx" {
                return chosenURL.deletingPathExtension().appendingPathExtension("docx")
            } else {
                return chosenURL
            }
        }()

        // Snapshot answers to avoid races.
        let answersSnapshot = self.answers

        // Update UI state.
        self.errorMessage = nil
        self.isGenerating = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let finalURL = try GeneratorService()
                    .generate(templateURL: tplURL,
                              answers: answersSnapshot,
                              destinationURL: saveURL)

                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.errorMessage = nil
                    NSWorkspace.shared.open(finalURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: Internal helpers -----------------------------------------------

    /// Called by Open-panel or drag-and-drop.
    func openTemplate(at url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        templateURL = url
        do {
            elements = try parser.parse(templateURL: url)
            errorMessage = nil
        } catch {
            elements = [.plainText(content: "Failed to load template.")]
            errorMessage = "Failed to load template: \(error.localizedDescription)"
        }
    }
}
