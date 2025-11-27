//
//  PersistenceService.swift
//  Legal Automator
//
//  Created by Rodney S. on 27/11/2025.
//  Handles saving and loading questionnaire answers to/from disk.
//

import Foundation

// MARK: - Persistence Errors

enum PersistenceError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case fileAccessDenied
    case invalidData

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode answers for saving."
        case .decodingFailed:
            return "Failed to decode saved answers."
        case .fileAccessDenied:
            return "Unable to access the answers file."
        case .invalidData:
            return "The saved answers file is corrupted or invalid."
        }
    }
}

// MARK: - Saved Answers Model

/// Represents a saved questionnaire session
struct SavedAnswers: Codable {
    let templateName: String
    let templatePath: String
    let savedDate: Date
    let answers: [String: AnyCodable]

    var displayName: String {
        "\(templateName) - \(savedDate.formatted(date: .abbreviated, time: .shortened))"
    }
}

// MARK: - Type-erased Codable wrapper

/// Wrapper to make Any values Codable for persistence
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let date = try? container.decode(Date.self) {
            value = date
        } else if let array = try? container.decode([[String: AnyCodable]].self) {
            // Convert back to [String: Any]
            value = array.map { dict in
                dict.mapValues { $0.value }
            }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw PersistenceError.invalidData
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let date as Date:
            try container.encode(date)
        case let array as [[String: Any]]:
            let codableArray = array.map { dict in
                dict.mapValues { AnyCodable($0) }
            }
            try container.encode(codableArray)
        case let dict as [String: Any]:
            let codableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        default:
            throw PersistenceError.encodingFailed
        }
    }
}

// MARK: - Persistence Service

final class PersistenceService {

    // MARK: - File Management

    /// Returns the default directory for saved answers
    private static var answersDirectory: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("Legal Automator Answers", isDirectory: true)
    }

    /// Ensures the answers directory exists
    private static func ensureDirectoryExists() throws {
        let dir = answersDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Save Answers

    /// Saves the current answers to a JSON file
    /// - Parameters:
    ///   - answers: The answers dictionary to save
    ///   - templateURL: The template these answers are for
    /// - Returns: URL of the saved file
    static func saveAnswers(_ answers: [String: Any], for templateURL: URL) throws -> URL {
        try ensureDirectoryExists()

        // Convert answers to codable format
        let codableAnswers = answers.mapValues { AnyCodable($0) }

        let saved = SavedAnswers(
            templateName: templateURL.deletingPathExtension().lastPathComponent,
            templatePath: templateURL.path,
            savedDate: Date(),
            answers: codableAnswers
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(saved)

        // Create filename based on template name and timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(saved.templateName)-\(timestamp).json"
        let fileURL = answersDirectory.appendingPathComponent(filename)

        try data.write(to: fileURL)
        return fileURL
    }

    // MARK: - Load Answers

    /// Loads answers from a saved file
    /// - Parameter fileURL: The file to load from
    /// - Returns: The answers dictionary
    static func loadAnswers(from fileURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: fileURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let saved = try decoder.decode(SavedAnswers.self, from: data)

        // Convert back to [String: Any]
        return saved.answers.mapValues { $0.value }
    }

    // MARK: - List Saved Answers

    /// Lists all saved answer files for a given template
    /// - Parameter templateURL: The template to find saved answers for
    /// - Returns: Array of SavedAnswers sorted by date (newest first)
    static func listSavedAnswers(for templateURL: URL) throws -> [SavedAnswers] {
        try ensureDirectoryExists()

        let templateName = templateURL.deletingPathExtension().lastPathComponent
        let contents = try FileManager.default.contentsOfDirectory(
            at: answersDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let saved: [SavedAnswers] = contents.compactMap { url in
            guard url.pathExtension == "json",
                  url.lastPathComponent.hasPrefix(templateName),
                  let data = try? Data(contentsOf: url),
                  let saved = try? decoder.decode(SavedAnswers.self, from: data) else {
                return nil
            }
            return saved
        }

        return saved.sorted { $0.savedDate > $1.savedDate }
    }

    // MARK: - Auto-Save

    /// Gets the auto-save file URL for a template
    private static func autoSaveURL(for templateURL: URL) -> URL {
        let templateName = templateURL.deletingPathExtension().lastPathComponent
        let filename = "\(templateName)-autosave.json"
        return answersDirectory.appendingPathComponent(filename)
    }

    /// Auto-saves answers (overwrites previous auto-save)
    static func autoSaveAnswers(_ answers: [String: Any], for templateURL: URL) throws {
        try ensureDirectoryExists()

        let codableAnswers = answers.mapValues { AnyCodable($0) }

        let saved = SavedAnswers(
            templateName: templateURL.deletingPathExtension().lastPathComponent,
            templatePath: templateURL.path,
            savedDate: Date(),
            answers: codableAnswers
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(saved)
        let fileURL = autoSaveURL(for: templateURL)

        try data.write(to: fileURL, options: .atomic)
    }

    /// Loads the auto-saved answers if they exist
    static func loadAutoSave(for templateURL: URL) throws -> [String: Any]? {
        let fileURL = autoSaveURL(for: templateURL)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return try loadAnswers(from: fileURL)
    }

    /// Deletes the auto-save file for a template
    static func clearAutoSave(for templateURL: URL) throws {
        let fileURL = autoSaveURL(for: templateURL)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
