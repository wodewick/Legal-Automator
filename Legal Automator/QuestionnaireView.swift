//
//  QuestionnaireView 2.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//


import SwiftUI

struct QuestionnaireView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        List {
            ForEach(viewModel.elements) { element in
                QuestionnaireRow(element: element,
                                 textBinding: Binding(
                                    get: { viewModel.answers[element.key] ?? "" },
                                    set: { viewModel.answers[element.key] = $0 }
                                 )
                )
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Row renderer

private struct QuestionnaireRow: View {
    let element: TemplateElement

    /// Minimal binding used for text-like values in this scaffold.
    /// You will likely replace this with a typed answer store.
    @Binding var textBinding: String

    var body: some View {
        switch element.kind {
        case .text:
            TextField(element.prompt, text: $textBinding)
        case .number:
            TextField(element.prompt, text: $textBinding)
                .keyboardType(.numbersAndPunctuation)
        case .date:
            // Store as ISO string in this scaffold; adapt to your answer model as needed.
            DatePicker(element.prompt,
                       selection: Binding(
                        get: { Self.date(from: textBinding) ?? Date() },
                        set: { textBinding = Self.iso8601(from: $0) }
                       ),
                       displayedComponents: .date)
        case .toggle:
            Toggle(element.prompt,
                   isOn: Binding(
                    get: { (textBinding as NSString).boolValue },
                    set: { textBinding = $0 ? "true" : "false" }
                   )
            )
        case .picker:
            Picker(element.prompt,
                   selection: Binding(
                    get: { textBinding },
                    set: { textBinding = $0 }
                   )
            ) {
                ForEach(element.options ?? [], id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        case .group:
            Section(element.prompt) {
                ForEach(element.children ?? []) { child in
                    QuestionnaireRow(element: child,
                                     textBinding: Binding(
                                        get: { textBinding }, // share or adjust per child key as needed
                                        set: { textBinding = $0 }
                                     )
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private static func date(from string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    private static func iso8601(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}