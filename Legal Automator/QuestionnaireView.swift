import SwiftUI

struct QuestionnaireView: View {
    let elements: [TemplateElement]
    @Binding var answers: [String: Any]

    var body: some View {
        // Use .grouped for macOS form styling
        Form {
            ForEach(elements, id: \.id) { element in
                // Using a helper view to keep the switch statement clean
                view(for: element)
            }
        }
        .formStyle(.grouped) // Use .grouped for macOS
        .padding()
    }

    // This is a view builder function to make the body cleaner
    @ViewBuilder
    private func view(for element: TemplateElement) -> some View {
        switch element {
        // CORRECTED: Added the missing 'id' parameter (as '_') to match the enum definition
        case .textField(let name, let label, let hint, let type):
            // Use a specific view for each text field type
            switch type {
            case .currency:
                TextField(label, value: currencyBinding(for: name), format: .currency(code: "USD"), prompt: Text(hint))
            case .number:
                TextField(label, value: doubleBinding(for: name), format: .number, prompt: Text(hint))
            default: // .text
                TextField(label, text: textBinding(for: name), prompt: Text(hint))
            }

        case .conditional(_, let name, let label, let subElements):
            Toggle(label, isOn: boolBinding(for: name))
            if boolBinding(for: name).wrappedValue {
                QuestionnaireView(elements: subElements, answers: $answers)
                    .padding(.leading)
            }
            
        case .repeatingGroup(_, let name, let label, let templateElements):
            GroupBox(label) {
                // Get the binding to the array of answers for this group
                let groupAnswersBinding = repeatingGroupBinding(for: name)
                
                // List each item in the group
                if !groupAnswersBinding.wrappedValue.isEmpty {
                    ForEach(groupAnswersBinding) { itemBinding in
                        HStack {
                            // Recursively create the form for the item
                            QuestionnaireView(elements: templateElements, answers: itemBinding)
                            
                            // Remove button for this item
                            Button(role: .destructive) {
                                // Find the index of the item to remove
                                if let index = answers[name, as: [[String: Any]].self, default: []].firstIndex(where: { $0["id"] as? UUID == itemBinding.wrappedValue["id"] as? UUID }) {
                                    answers[name, as: [[String: Any]].self]?.remove(at: index)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                
                // Add button for the group
                Button("Add \(label)") {
                    // Append a new empty dictionary with a unique ID
                    let newItem: [String: Any] = ["id": UUID()]
                    var currentItems = answers[name, as: [[String: Any]].self, default: []]
                    currentItems.append(newItem)
                    answers[name] = currentItems
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
        case .staticText(_, let content):
            Text(content)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Binding Helpers

    private func textBinding(for key: String) -> Binding<String> {
        return Binding<String>(
            get: { self.answers[key] as? String ?? "" },
            set: { self.answers[key] = $0 }
        )
    }

    private func boolBinding(for key: String) -> Binding<Bool> {
        return Binding<Bool>(
            get: { self.answers[key] as? Bool ?? false },
            set: { self.answers[key] = $0 }
        )
    }
    
    private func doubleBinding(for key: String) -> Binding<Double> {
        return Binding<Double>(
            get: { self.answers[key] as? Double ?? 0.0 },
            set: { self.answers[key] = $0 }
        )
    }
    
    private func currencyBinding(for key: String) -> Binding<Double> {
        // Currency is just a Double, formatted differently by the view
        return doubleBinding(for: key)
    }
    
    private func repeatingGroupBinding(for key: String) -> Binding<[Binding<[String: Any]>]> {
        return Binding<[Binding<[String: Any]>]>(
            get: {
                guard let array = self.answers[key] as? [[String: Any]] else { return [] }
                return array.indices.map { index in
                    Binding<[String: Any]>(
                        get: {
                            guard let array = self.answers[key] as? [[String: Any]], array.indices.contains(index) else { return [:] }
                            return array[index]
                        },
                        set: { newValue in
                            guard var array = self.answers[key] as? [[String: Any]], array.indices.contains(index) else { return }
                            array[index] = newValue
                            self.answers[key] = array
                        }
                    )
                }
            },
            set: { newBindings in
                self.answers[key] = newBindings.map { $0.wrappedValue }
            }
        )
    }
}

// MARK: - Dictionary Extension
// Helper extension to make accessing typed values in the [String: Any] dictionary safer and cleaner.
extension Dictionary where Key == String, Value == Any {
    subscript<T>(key: String, as type: T.Type, default defaultValue: @autoclosure () -> T) -> T {
        get {
            return (self[key] as? T) ?? defaultValue()
        }
        set {
            self[key] = newValue
        }
    }
    
    subscript<T>(key: String, as type: T.Type) -> T? {
        get {
            return self[key] as? T
        }
        set {
            self[key] = newValue
        }
    }
}

