//
//  ContentView.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header area
            headerView
            
            Divider()

            // Main content area
            if _viewModel.wrappedValue.templateURL == nil {
                DropTargetView(
                    promptTitle: "Document Automator",
                    promptSubtitle: "Drop a .docx here or click Select Template…",
                    onDropURL: { url in _viewModel.wrappedValue.openTemplate(at: url) }
                ) {
                    Button("Select Template...") { _viewModel.wrappedValue.selectTemplate() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Show the questionnaire form once a template is loaded
                QuestionnaireView(elements: _viewModel.wrappedValue.templateElements, answers: $viewModel.answers)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { _viewModel.wrappedValue.errorMessage != nil },
            set: { newValue in if newValue == false { _viewModel.wrappedValue.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { _viewModel.wrappedValue.errorMessage = nil }
        } message: {
            Text(_viewModel.wrappedValue.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var headerView: some View {
        HStack {
            Text(_viewModel.wrappedValue.templateURL?.lastPathComponent ?? "No Template Selected")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button("Generate Document") { _viewModel.wrappedValue.generateDocument() }
                .disabled(_viewModel.wrappedValue.templateURL == nil)
        }
        .padding()
        .frame(height: 55)
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
