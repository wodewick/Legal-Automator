//
//  ContentViewModel.swift
//  Legal Automator
//
//  Created by Rodney Serkowski on 27/7/2025.
//  Updated: 04/09/2025 – separate busy state from error text, use allowedContentTypes
//  on NSSavePanel with fallback, and enforce .docx extension on saves.
//  Updated: 04/09/2025 (2) – add persistent Recent Templates (bookmarks), pin/unpin,
//  Reveal in Finder, and iCloud KVS sync.
//
import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Recent Templates Model
struct RecentTemplate: Codable, Equatable {
    let name: String            // Display name (lastPathComponent)
    let bookmark: Data          // Security-scoped bookmark to the .docx
    let lastUsed: Date
    var pinned: Bool

    init(name: String, bookmark: Data, lastUsed: Date, pinned: Bool = false) {
        self.name = name
        self.bookmark = bookmark
        self.lastUsed = lastUsed
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey { case name, bookmark, lastUsed, pinned }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        bookmark = try c.decode(Data.self, forKey: .bookmark)
        lastUsed = try c.decode(Date.self, forKey: .lastUsed)
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
    }
}

// MARK: - ViewModel
/// Top-level view-model orchestrating template selection, parsing, and (later)
/// document generation.
final class ContentViewModel: ObservableObject {

    // MARK: Dependencies
    private let parser = ParserService()

    // MARK: Template state
    @Published var templateURL: URL?
    @Published private(set) var elements: [TemplateElement] = [
        .plainText(content: "Select a template to begin.")
    ]
    /// Answers keyed by variable / group name.  GeneratorService will consume this later.
    @Published var answers: [String: Any] = [:]

    // MARK: UI feedback
    /// Present only real errors to the operator. Do not overload with status text.
    @Published var errorMessage: String?
    /// Busy flag for long-running work (e.g., generation). Views can show a spinner.
    @Published var isGenerating: Bool = false

    // MARK: Recent Templates
    @Published private(set) var recentTemplates: [RecentTemplate] = []
    private let recentsKey = "RecentTemplateBookmarksV1"
    private let recentsLimit = 5
    private let kvs: NSUbiquitousKeyValueStore? = {
        if FileManager.default.ubiquityIdentityToken != nil {
            return NSUbiquitousKeyValueStore.default
        } else {
            print("iCloud not available, using local storage only")
            return nil
        }
    }()

    init() {
        loadRecents()
        // Best-effort: adopt iCloud if we have nothing local
        syncFromKVSIfLocalEmpty()

        // Only register for notifications if KVS is available
        if let kvs = kvs {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(kvStoreChanged(_:)),
                                                   name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                   object: kvs)
            kvs.synchronize()
        }

        diagnosticCheck()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Back-compat shim: some older views still reference `templateElements`.
    var templateElements: [TemplateElement] { elements }

    // MARK: User actions ----------------------------------------------------

    /// Show an Open dialog so the operator can choose a *.docx* template.
    func selectTemplate() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        } else {
            panel.allowedFileTypes = ["docx"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select a .docx template"

        if panel.runModal() == .OK, let url = panel.url {
            openTemplate(at: url)
        }
    }

    /// Merge `answers` into `templateURL` to produce an output document.
    @MainActor
    func generateDocument() {
        guard let tplURL = templateURL else {
            errorMessage = "Please select a template before generating a document."
            return
        }

        let panel = NSSavePanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        } else {
            panel.allowedFileTypes = ["docx"]
        }
        panel.nameFieldStringValue = "Merged-Document.docx"

        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }

        // Ensure the destination ends with .docx (handles no extension or a wrong one).
        let saveURL: URL = {
            let ext = chosenURL.pathExtension.lowercased()
            if ext.isEmpty {
                return chosenURL.appendingPathExtension("docx")
            } else if ext != "docx" {
                return chosenURL.deletingPathExtension().appendingPathExtension("docx")
            } else {
                return chosenURL
            }
        }()

        // Snapshot answers to avoid races.
        let answersSnapshot = self.answers

        // Update UI state.
        self.errorMessage = nil
        self.isGenerating = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let finalURL = try GeneratorService()
                    .generate(templateURL: tplURL,
                              answers: answersSnapshot,
                              destinationURL: saveURL)

                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.errorMessage = nil
                    NSWorkspace.shared.open(finalURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Merge to a temporary file and open it for a quick preview (non-destructive).
    /// This does not prompt for a save location and respects the current answers snapshot.
    /// The file will be created in the user's temporary directory with a unique name.
    @MainActor
    func previewDocument() {
        guard let tplURL = templateURL else {
            errorMessage = "Please select a template before previewing a document."
            return
        }

        // Snapshot answers to avoid races.
        let answersSnapshot = self.answers
        self.errorMessage = nil
        self.isGenerating = true

        // Create a unique temporary destination with .docx extension
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fileName = "Preview-" + UUID().uuidString + ".docx"
        let tempURL = tempDir.appendingPathComponent(fileName)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let finalURL = try GeneratorService()
                    .generate(templateURL: tplURL,
                              answers: answersSnapshot,
                              destinationURL: tempURL)

                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.errorMessage = nil
                    // Open with the default .docx handler (e.g., Word/Pages). Non-destructive preview.
                    NSWorkspace.shared.open(finalURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: Internal helpers -----------------------------------------------

    /// Called by Open-panel, drag-and-drop, or the recents menu.
    func openTemplate(at url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        templateURL = url
        do {
            elements = try parser.parse(templateURL: url)
            errorMessage = nil
            rememberRecent(url: url)
        } catch {
            elements = [.plainText(content: "Failed to load template.")]
            errorMessage = "Failed to load template: \(error.localizedDescription)"
        }
    }

    // MARK: Recents API -----------------------------------------------------

    /// Store (or refresh) a recent template entry, keeping a max of `recentsLimit`.
    func rememberRecent(url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            var list = recentTemplates
            let name = url.lastPathComponent

            // Preserve pinned state if we already know this template by name
            let wasPinned = list.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.pinned ?? false

            // Deduplicate by name and (best-effort) bookmark bytes.
            list.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if let idx = list.firstIndex(where: { $0.bookmark == bookmark }) {
                list.remove(at: idx)
            }

            // Insert newest at front
            list.insert(RecentTemplate(name: name,
                                       bookmark: bookmark,
                                       lastUsed: Date(),
                                       pinned: wasPinned),
                        at: 0)

            recentTemplates = list
            persistRecents()
        } catch {
            // Non-fatal; surface a soft error.
            self.errorMessage = "Could not save recent template: \(error.localizedDescription)"
        }
    }

    /// Open a recent template from its bookmark.
    func openRecent(_ item: RecentTemplate) {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: item.bookmark,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            openTemplate(at: url)
            // Re-remember to bump recency and refresh a stale bookmark.
            rememberRecent(url: url)
        } catch {
            self.errorMessage = "Unable to open recent template: \(error.localizedDescription)"
        }
    }

    /// Reveal a recent item in Finder.
    func revealRecent(_ item: RecentTemplate) {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: item.bookmark,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            let needsStop = url.startAccessingSecurityScopedResource()
            NSWorkspace.shared.activateFileViewerSelecting([url])
            if needsStop { url.stopAccessingSecurityScopedResource() }
            if isStale { rememberRecent(url: url) }
        } catch {
            self.errorMessage = "Unable to reveal in Finder: \(error.localizedDescription)"
        }
    }

    /// Toggle pin/unpin for a recent entry.
    func togglePinRecent(_ item: RecentTemplate) {
        if let idx = recentTemplates.firstIndex(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
            recentTemplates[idx].pinned.toggle()
            persistRecents()
        }
    }

    /// Remove all stored recent templates.
    func clearRecentTemplates() {
        recentTemplates.removeAll()
        UserDefaults.standard.removeObject(forKey: recentsKey)
        kvs?.removeObject(forKey: recentsKey)
        kvs?.synchronize()
    }

    private func persistRecents() {
        // Sort pinned first, then by lastUsed desc; trim to recentsLimit.
        recentTemplates.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.lastUsed > rhs.lastUsed
        }
        if recentTemplates.count > recentsLimit {
            recentTemplates = Array(recentTemplates.prefix(recentsLimit))
        }
        do {
            let data = try JSONEncoder().encode(recentTemplates)
            UserDefaults.standard.set(data, forKey: recentsKey)
            kvs?.set(data, forKey: recentsKey)
            kvs?.synchronize()
        } catch {
            // Non-fatal; do not block UI.
        }
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: recentsKey) else { return }
        if let decoded = try? JSONDecoder().decode([RecentTemplate].self, from: data) {
            recentTemplates = Array(decoded.sorted(by: { (l, r) -> Bool in
                if l.pinned != r.pinned { return l.pinned && !r.pinned }
                return l.lastUsed > r.lastUsed
            }).prefix(recentsLimit))
        } else {
            // If decoding fails, clear the corrupted data.
            UserDefaults.standard.removeObject(forKey: recentsKey)
        }
    }

    private func syncFromKVSIfLocalEmpty() {
        guard recentTemplates.isEmpty, let kvs = kvs, let data = kvs.data(forKey: recentsKey) else { return }
        if let decoded = try? JSONDecoder().decode([RecentTemplate].self, from: data) {
            recentTemplates = Array(decoded.sorted(by: { (l, r) -> Bool in
                if l.pinned != r.pinned { return l.pinned && !r.pinned }
                return l.lastUsed > r.lastUsed
            }).prefix(recentsLimit))
        }
    }

    @objc private func kvStoreChanged(_ note: Notification) {
        guard let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              reason == NSUbiquitousKeyValueStoreServerChange ||
              reason == NSUbiquitousKeyValueStoreInitialSyncChange else { return }
        // Only adopt iCloud data if we currently have none (avoid clobbering local)
        syncFromKVSIfLocalEmpty()
    }

    private func diagnosticCheck() {
        #if DEBUG
        print("=== Legal Automator Diagnostics ===")
        print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print("iCloud Available: \(FileManager.default.ubiquityIdentityToken != nil)")
        print("Team ID: \(Bundle.main.object(forInfoDictionaryKey: "TeamIdentifierPrefix") ?? "Unknown")")
        print("Sandbox: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)")
        print("===================================")
        #endif
    }
}
