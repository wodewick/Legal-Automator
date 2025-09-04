//
//  Legal_AutomatorApp.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//  Updated: 04/09/2025 – App-level Commands, environmentObject wiring, and Open Recent submenu
//  Updated: 04/09/2025 – macOS file-open bridge + Settings scene (privacy & logs)
//

import SwiftUI
import AppKit

// MARK: - App Notifications
extension Notification.Name {
    /// Posted when a .docx file is opened from Finder / drag-and-drop.
    static let openTemplateRequested = Notification.Name("OpenTemplateRequested")
}

// MARK: - AppDelegate (handles files opened from Finder / Dock)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        NotificationCenter.default.post(name: .openTemplateRequested, object: url)
    }
}

// MARK: - Settings
struct AppSettingsView: View {
    @AppStorage("viewOnlyMode") private var viewOnlyMode: Bool = false
    @AppStorage("logRetentionDays") private var logRetentionDays: Int = 90

    var body: some View {
        Form {
            Section("Privacy & Handling") {
                Toggle("View-only mode (do not save working copies)", isOn: $viewOnlyMode)
                Text("When enabled, Legal Automator avoids writing intermediate files to disk where possible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Compliance Logs") {
                Stepper(value: $logRetentionDays, in: 7...365) {
                    Text("Retention period: \(logRetentionDays) days")
                }
                Text("Logs older than the retention period should be purged by the logging subsystem.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

@main
struct LegalAutomatorApp: App {
    @StateObject private var viewModel = ContentViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate) private var appDelegate

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

        Settings {
            AppSettingsView()
        }
    }
}
