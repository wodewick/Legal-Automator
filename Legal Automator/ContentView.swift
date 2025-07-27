//
//  ContentView.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header area
            headerView
            
            Divider()

            // Main content area
            if _viewModel.wrappedValue.templateURL == nil {
                // Show a welcome/selection view if no template is loaded
                VStack(spacing: 20) {
                    Spacer()
                    Text("Document Automator")
                        .font(.largeTitle)
                    Text("Select a .docx template to begin.")
                        .foregroundStyle(.secondary)
                    Button("Select Template...") { _viewModel.wrappedValue.selectTemplate() }
                    Spacer()
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
