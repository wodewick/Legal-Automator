//
//  ContentView.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//  Updated: 04/09/2025 – remove _viewModel.wrappedValue usage, wire isGenerating,
//  add keyboard shortcuts, and polish drop target visuals.
//  Updated: 04/09/2025 (2) – add status bar, disable form while generating, a11y hints
//  Updated: 04/09/2025 (3) – switch to @EnvironmentObject for App-level Commands
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header area
            headerView

            // Lightweight status bar
            statusBarView

            Divider()

            // Main content area
            if viewModel.templateURL == nil {
                DropTargetView(
                    promptTitle: "Document Automator",
                    promptSubtitle: "Drop a .docx here or click Select Template…",
                    onDropURL: { url in viewModel.openTemplate(at: url) }
                ) {
                    Button("Select Template…") {
                        viewModel.selectTemplate()
                    }
                    .keyboardShortcut("o", modifiers: [.command])
                    .help("Open a .docx template (⌘O)")
                    .accessibilityLabel("Select Template")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
            } else {
                // Show the questionnaire form once a template is loaded
                QuestionnaireView(
                    elements: viewModel.templateElements,
                    answers: $viewModel.answers
                )
                // Prevent edits during generation to avoid race conditions
                .disabled(viewModel.isGenerating)
            }
        }
        // Error alert (real errors only; progress uses isGenerating)
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in if newValue == false { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Text(viewModel.templateURL?.lastPathComponent ?? "No Template Selected")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(
                    viewModel.templateURL == nil
                    ? "No template selected"
                    : "Selected template \(viewModel.templateURL!.lastPathComponent)"
                )

            Spacer()

            if viewModel.isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .help("Generating the merged document…")
                    .accessibilityLabel("Generating document")
            }

            Button("Generate Document") {
                viewModel.generateDocument()
            }
            .disabled(viewModel.templateURL == nil || viewModel.isGenerating)
            .keyboardShortcut("e", modifiers: [.command])
            .help("Generate a merged Word document (⌘E)")
            .accessibilityLabel("Generate Document")
        }
        .padding()
        .frame(height: 55)
    }

    private var statusBarView: some View {
        HStack(spacing: 8) {
            if let url = viewModel.templateURL {
                Label {
                    Text(url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "doc")
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Template path \(url.path)")
            } else {
                Text("Ready")
                    .accessibilityLabel("Ready")
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

// MARK: - DropTargetView
private struct DropTargetView<Footer: View>: View {
    let promptTitle: String
    let promptSubtitle: String
    let onDropURL: (URL) -> Void
    @ViewBuilder var footer: () -> Footer

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            Text(promptTitle)
                .font(.largeTitle)

            Text(promptSubtitle)
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                    )

                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 36))
                        .accessibilityHidden(true)

                    Text("Drop .docx file here")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .frame(maxWidth: 460, minHeight: 160)
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                // Attempt to load the first file URL provider
                guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
                    return false
                }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    guard error == nil else { return }
                    let url: URL? = (item as? URL) ?? (item as? NSURL)?.absoluteURL
                    if let url, url.pathExtension.lowercased() == "docx" {
                        DispatchQueue.main.async {
                            onDropURL(url)
                        }
                    }
                }
                return true
            }

            footer()

            Spacer(minLength: 0)
        }
        .padding()
    }
}
