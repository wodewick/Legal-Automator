//
//  Legal_AutomatorApp.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//  Updated: 04/09/2025 – App-level Commands, environmentObject wiring, and Open Recent submenu
//

import SwiftUI

@main
struct LegalAutomatorApp: App {
    @StateObject private var viewModel = ContentViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                // Set a sensible default size for a Mac app
                .frame(minWidth: 400, idealWidth: 600, minHeight: 500, idealHeight: 700)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Template…") {
                    viewModel.selectTemplate()
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(viewModel.isGenerating)

                if !viewModel.recentTemplates.isEmpty {
                    Menu("Open Recent Template") {
                        ForEach(viewModel.recentTemplates.indices, id: \.self) { i in
                            let item = viewModel.recentTemplates[i]
                            Menu(item.pinned ? "\(item.name) ★" : item.name) {
                                Button("Open") {
                                    viewModel.openRecent(item)
                                }
                                Button("Reveal in Finder") {
                                    viewModel.revealRecent(item)
                                }
                                Divider()
                                Button(item.pinned ? "Unpin" : "Pin") {
                                    viewModel.togglePinRecent(item)
                                }
                            }
                        }
                        Divider()
                        Button("Clear Recent Templates") {
                            viewModel.clearRecentTemplates()
                        }
                    }
                }

                Button("Generate Document") {
                    viewModel.generateDocument()
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(viewModel.templateURL == nil || viewModel.isGenerating)
            }
        }
    }
}
