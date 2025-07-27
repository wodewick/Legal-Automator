import SwiftUI

struct QuestionnaireView: View {
    // This is now correctly typed as an array of TemplateElement
    let elements: [TemplateElement]
    @Binding var answers: [String: Any]

    var body: some View {
        Form {
            // This now correctly tells the ForEach loop how to identify each element
            ForEach(elements, id: \.id) { element in
                switch element {
                case .textField(_, let name, let label, let hint):
                    TextField(label, text: textBinding(for: name), prompt: Text(hint))
                    
                case .conditional(_, let name, let label, let subElements):
                    Toggle(label, isOn: boolBinding(for: name))
                    // If the toggle is on, recursively show the sub-elements
                    if boolBinding(for: name).wrappedValue {
                        // Indent the nested section
                        QuestionnaireView(elements: subElements, answers: $answers)
                            .padding(.leading)
                    }
                    
                case .repeatingGroup(_, _, let label, _):
                    // Placeholder UI for repeating sections.
                    // A full implementation would manage an array of answers here.
                    GroupBox(label) {
                        Text("Repeating section UI will go here.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                    
                case .staticText(_, let content):
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    // MARK: - Binding Helpers

    // Helper to create a String binding to a dictionary key
    private func textBinding(for key: String) -> Binding<String> {
        return Binding<String>(
            get: { self.answers[key] as? String ?? "" },
            set: { self.answers[key] = $0 }
        )
    }

    // Helper to create a Bool binding to a dictionary key
    private func boolBinding(for key: String) -> Binding<Bool> {
        return Binding<Bool>(
            get: { self.answers[key] as? Bool ?? false },
            set: { self.answers[key] = $0 }
        )
    }
}

