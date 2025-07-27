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
            if viewModel.templateURL == nil {
                // Show a welcome/selection view if no template is loaded
                VStack(spacing: 20) {
                    Spacer()
                    Text("Document Automator")
                        .font(.largeTitle)
                    Text("Select a .docx template to begin.")
                        .foregroundStyle(.secondary)
                    Button("Select Template...", action: viewModel.selectTemplate)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Show the questionnaire form once a template is loaded
                QuestionnaireView(elements: viewModel.templateElements, answers: $viewModel.answers)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        }, message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        })
    }

    private var headerView: some View {
        HStack {
            Text(viewModel.templateURL?.lastPathComponent ?? "No Template Selected")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button("Generate Document", action: viewModel.generateDocument)
                .disabled(viewModel.templateURL == nil)
        }
        .padding()
        .frame(height: 55)
    }
}
