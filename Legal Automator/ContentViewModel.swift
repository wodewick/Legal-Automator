import SwiftUI
import Foundation
import UniformTypeIdentifiers // <-- Make sure this import is here

@MainActor
class ContentViewModel: ObservableObject {
    @Published var templateURL: URL?
    // This is now correctly typed as an array of TemplateElement
    @Published var templateElements: [TemplateElement] = []
    @Published var answers: [String: Any] = [:]

    @Published var isLoading = false
    @Published var errorMessage: String?

    // In a real app, this would call your DocxParserService
    private func parseTemplate() {
        guard let url = templateURL else { return }
        
        isLoading = true
        
        // **MOCK DATA - Correctly typed**
        // This now correctly creates an array of [TemplateElement]
        self.templateElements = [
            .textField(id: UUID(), name: "client_name", label: "Client Name", hint: "e.g., John Smith"),
            .textField(id: UUID(), name: "matter_number", label: "Matter Number", hint: "e.g., 12345"),
            .conditional(id: UUID(), name: "is_urgent", label: "Is this matter urgent?", elements: [
                .staticText(id: UUID(), content: "Note: Urgent matters will be prioritized."),
                .textField(id: UUID(), name: "urgency_reason", label: "Reason for Urgency", hint: "e.g., Court deadline")
            ]),
            .repeatingGroup(id: UUID(), name: "directors", label: "Directors", templateElements: [
                .textField(id: UUID(), name: "director_name", label: "Director Name", hint: "")
            ])
        ]
        
        // Set a default value for the conditional toggle
        self.answers["is_urgent"] = false
        
        isLoading = false
    }

    // MARK: - User Actions

    func selectTemplate() {
        let openPanel = NSOpenPanel()
        // This now uses the correct syntax for the .docx file type
        openPanel.allowedContentTypes = [UTType.openXMLWordProcessingMLDocument]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        
        if openPanel.runModal() == .OK {
            self.templateURL = openPanel.url
            parseTemplate()
        }
    }
    
    func generateDocument() {
        guard templateURL != nil else {
            errorMessage = "Please select a template first."
            return
        }
        
        let savePanel = NSSavePanel()
        // This also uses the correct syntax for the .docx file type
        savePanel.allowedContentTypes = [UTType.openXMLWordProcessingMLDocument]
        savePanel.nameFieldStringValue = "Generated Document.docx"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            // Here you would call your DocxGeneratorService
            // For now, we'll just print the data.
            print("Generating document at: \(outputURL.path)")
            print("With answers: \(answers)")
        }
    }
}
