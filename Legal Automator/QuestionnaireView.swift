import SwiftUI

struct QuestionnaireView: View {
    let elements: [TemplateElement]
    @Binding var answers: [String: Any]

    var body: some View {
        Form {
            ForEach(elements) { element in
                view(for: element)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func view(for element: TemplateElement) -> some View {
        switch element {

        // MARK: - Plain text

        case .plainText(_, let content):
            Text(content)
                .font(.caption)
                .foregroundStyle(.secondary)

        // MARK: - Single‑value variable

        case .variable(_, let name, let labelOpt, let hintOpt, let type):
            switch type {
            case .text:
                TextField(labelOpt ?? name.capitalized,
                          text: textBinding(for: name),
                          prompt: Text(hintOpt ?? "Enter \(labelOpt ?? name)"))
                    .textFieldStyle(.roundedBorder)
                    .padding(.vertical, 2)
                    .help(hintOpt ?? "")

            case .toggle:
                Toggle(labelOpt ?? name.capitalized, isOn: boolBinding(for: name))
                    .padding(.vertical, 2)
                    .help(hintOpt ?? "")

            case .date:
                DatePicker(labelOpt ?? name.capitalized,
                          selection: dateBinding(for: name),
                          displayedComponents: [.date])
                    .padding(.vertical, 2)
                    .help(hintOpt ?? "")
            }

        // MARK: - Conditional section

        case .conditional(_, let name, let labelOpt, let elements):
            Toggle(labelOpt ?? name.capitalized, isOn: boolBinding(for: name))
            if boolBinding(for: name).wrappedValue {
                QuestionnaireView(elements: elements, answers: $answers)
                    .padding(.leading)
            }

        // MARK: - Repeating group

        case .repeatingGroup(_, let group, let labelOpt, let templateElements):
            Section(header: Text(labelOpt ?? group.capitalized).font(.headline)) {
                let groupBinding = repeatingArrayBinding(for: group)

                if !groupBinding.wrappedValue.isEmpty {
                    ForEach(groupBinding.wrappedValue.indices, id: \.self) { index in
                        DisclosureGroup("Item \(index + 1)") {
                            let itemBinding = Binding<[String: Any]>(
                                get: { groupBinding.wrappedValue[index] },
                                set: { groupBinding.wrappedValue[index] = $0 }
                            )
                            QuestionnaireView(elements: templateElements, answers: itemBinding)

                            Button("Delete", role: .destructive) {
                                groupBinding.wrappedValue.remove(at: index)
                            }
                            .padding(.top, 4)
                        }
                    }
                }

                Button("Add \(singularForm(of: labelOpt ?? group))") {
                    var arr = groupBinding.wrappedValue
                    var newItem: [String: Any] = [:]
                    newItem["id"] = UUID()
                    arr.append(newItem)
                    groupBinding.wrappedValue = arr
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Helpers

    /// Attempts to convert a plural word to singular for better UX.
    private func singularForm(of word: String) -> String {
        if word.hasSuffix("ies") && word.count > 3 {
            return String(word.dropLast(3)) + "y"
        } else if word.hasSuffix("s") && word.count > 1 {
            return String(word.dropLast())
        } else {
            return word
        }
    }

    // MARK: - Bindings

    private func textBinding(for key: String) -> Binding<String> {
        Binding<String>(
            get: { (answers[key] as? String) ?? "" },
            set: { answers[key] = $0 }
        )
    }

    private func boolBinding(for key: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { (answers[key] as? Bool) ?? false },
            set: { answers[key] = $0 }
        )
    }

    private func doubleBinding(for key: String) -> Binding<Double> {
        Binding<Double>(
            get: {
                if let d = answers[key] as? Double { return d }
                if let s = answers[key] as? String, let d = Double(s) { return d }
                return 0
            },
            set: { answers[key] = $0 }
        )
    }

    private func dateBinding(for key: String) -> Binding<Date> {
        Binding<Date>(
            get: { (answers[key] as? Date) ?? Date() },
            set: { answers[key] = $0 }
        )
    }

    private func repeatingArrayBinding(for key: String) -> Binding<[[String: Any]]> {
        Binding<[[String: Any]]>(
            get: { (answers[key] as? [[String: Any]]) ?? [] },
            set: { answers[key] = $0 }
        )
    }
}

// MARK: - Dictionary typed access helpers (optional)
extension Dictionary where Key == String, Value == Any {
    subscript<T>(safe key: String, as: T.Type) -> T? { self[key] as? T }
}
