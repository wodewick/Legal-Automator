import SwiftUI
import Foundation
import UniformTypeIdentifiers // <-- This import is important

@MainActor
class ContentViewModel: ObservableObject {
    @Published var templateURL: URL?
    // CORRECTED: This is now an array of [TemplateElement]
    @Published var templateElements: [TemplateElement] = []
    @Published var answers: [String: Any] = [:]

    @Published var isLoading = false
    @Published var errorMessage: String?

    private func parseTemplate() {
        guard let url = templateURL else { return }
        
        isLoading = true
        
        // CORRECTED: This mock data now correctly creates [TemplateElement]
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
        
        self.answers["is_urgent"] = false
        
        isLoading = false
    }

    // MARK: - User Actions

    func selectTemplate() {
        let openPanel = NSOpenPanel()
        // CORRECTED: This uses the correct UTType for .docx files
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
        // CORRECTED: This also uses the correct UTType
        savePanel.allowedContentTypes = [UTType.openXMLWordProcessingMLDocument]
        savePanel.nameFieldStringValue = "Generated Document.docx"
        
        if savePanel.runModal() == .OK, let outputURL = savePanel.url {
            print("Generating document at: \(outputURL.path)")
            print("With answers: \(answers)")
        }
    }
}
