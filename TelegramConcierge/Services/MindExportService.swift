import Foundation

// MARK: - Mind Export Service

/// Handles exporting and importing all user data for portability
actor MindExportService {
    static let shared = MindExportService()
    
    // MARK: - Configuration
    
    /// Version for forward compatibility
    private let exportVersion = "1.1"
    
    /// File extension for mind exports
    static let fileExtension = "mind"
    
    /// Base app folder
    private let appFolder: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("LocalAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// Some newer LocalAgent state intentionally lives in ~/LocalAgent so it is
    /// easy for users to inspect and share outside the app sandbox.
    private let homeFolder: URL = {
        let folder = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("LocalAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    
    // MARK: - Export
    
    /// Export all user data to a ZIP file at the specified destination
    /// - Returns: URL to the exported file
    func exportMind(to destination: URL) async throws {
        let fm = FileManager.default
        
        // Create a temporary directory for assembly
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        
        // 1. Copy app-support files.
        for fileName in [
            "conversation.json",
            "context_usage.json",
            "contacts.json",
            "reminders.json",
            "calendar.json",
            "files_ledger.json",
            "documents_last_opened.json",
            "todos.json"
        ] {
            try copyItemIfExists(
                from: appFolder.appendingPathComponent(fileName),
                to: tempDir.appendingPathComponent(fileName)
            )
        }

        // 2. Copy app-support folders.
        for folderName in [
            "archive",
            "images",
            "documents",
            "tool_attachments",
            "projects"
        ] {
            try copyItemIfExists(
                from: appFolder.appendingPathComponent(folderName, isDirectory: true),
                to: tempDir.appendingPathComponent(folderName, isDirectory: true)
            )
        }

        // 3. Copy home-backed memory stores.
        try copyItemIfExists(
            from: homeFolder.appendingPathComponent("subagent_sessions", isDirectory: true),
            to: tempDir.appendingPathComponent("subagent_sessions", isDirectory: true)
        )

        // 4. Create mind_config.json with Keychain and UserDefaults data.
        let config = buildMindConfig()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let configData = try encoder.encode(config)
        try configData.write(to: tempDir.appendingPathComponent("mind_config.json"))
        
        // 5. Create ZIP archive using native macOS zip command.
        // Remove existing file if present
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        
        try await createZipArchive(from: tempDir, to: destination)
        
        print("[MindExportService] Exported mind to: \(destination.path)")
    }
    
    // MARK: - Import
    
    /// Import user data from a mind file
    /// - Parameter source: URL to the .mind file
    func importMind(from source: URL) async throws {
        let fm = FileManager.default
        
        // Create a temporary directory for extraction
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        
        // Extract ZIP using native macOS unzip command
        try await extractZipArchive(from: source, to: tempDir)
        
        // 1. Restore app-support files. Missing files in older backups clear
        // the current counterpart so import behaves like a real replacement.
        for fileName in [
            "conversation.json",
            "context_usage.json",
            "contacts.json",
            "reminders.json",
            "calendar.json",
            "files_ledger.json",
            "documents_last_opened.json",
            "todos.json"
        ] {
            try restoreFile(named: fileName, from: tempDir, to: appFolder)
        }

        // 2. Restore app-support folders.
        for folderName in [
            "archive",
            "images",
            "documents",
            "tool_attachments",
            "projects"
        ] {
            try restoreDirectory(named: folderName, from: tempDir, to: appFolder)
        }

        // 3. Restore home-backed memory stores.
        try restoreDirectory(named: "subagent_sessions", from: tempDir, to: homeFolder)

        // 4. Restore mind_config.json settings.
        // Fallback to any *_config.json for backward/forward compatibility.
        let preferredConfigSource = tempDir.appendingPathComponent("mind_config.json")
        let configSource: URL?
        if fm.fileExists(atPath: preferredConfigSource.path) {
            configSource = preferredConfigSource
        } else {
            let fallback = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix("_config.json") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .first
            configSource = fallback
        }
        
        if let configSource {
            let configData = try Data(contentsOf: configSource)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config = try decoder.decode(MindConfig.self, from: configData)
            try restoreMindConfig(config)
        }
        
        print("[MindExportService] Imported mind from: \(source.path)")
    }

    // MARK: - File Copy Helpers

    private func copyItemIfExists(from source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func restoreFile(named fileName: String, from tempDir: URL, to destinationDir: URL) throws {
        let source = tempDir.appendingPathComponent(fileName)
        let destination = destinationDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func restoreDirectory(named folderName: String, from tempDir: URL, to destinationDir: URL) throws {
        let source = tempDir.appendingPathComponent(folderName, isDirectory: true)
        let destination = destinationDir.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.copyItem(at: source, to: destination)
        } else {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - ZIP Operations (using native macOS commands)
    
    private func createZipArchive(from sourceDir: URL, to destination: URL) async throws {
        let fm = FileManager.default
        
        // Create zip in temp directory first, then copy to destination
        // This works around sandboxing: the subprocess can't write directly to user-selected paths
        let tempZip = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tempZip) }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = sourceDir
        process.arguments = ["-r", "-q", tempZip.path, "."]
        
        let pipe = Pipe()
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw MindExportError.zipFailed(errorMessage)
        }
        
        // Copy from temp to destination (this uses the security-scoped access granted by NSSavePanel)
        try fm.copyItem(at: tempZip, to: destination)
    }
    
    private func extractZipArchive(from source: URL, to destinationDir: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", source.path, "-d", destinationDir.path]
        
        let pipe = Pipe()
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw MindExportError.unzipFailed(errorMessage)
        }
    }
    
    // MARK: - Mind Config
    
    private struct MindConfig: Codable {
        let version: String
        let exportDate: Date
        let persona: PersonaConfig
        let fileDescriptions: [String: String]
    }
    
    private struct PersonaConfig: Codable {
        let assistantName: String?
        let userName: String?
        let userContext: String?
        let structuredUserContext: String?
    }
    
    private func buildMindConfig() -> MindConfig {
        // Load persona settings from Keychain
        let persona = PersonaConfig(
            assistantName: KeychainHelper.load(key: KeychainHelper.assistantNameKey),
            userName: KeychainHelper.load(key: KeychainHelper.userNameKey),
            userContext: KeychainHelper.load(key: KeychainHelper.userContextKey),
            structuredUserContext: KeychainHelper.load(key: KeychainHelper.structuredUserContextKey)
        )
        
        // Load file descriptions from UserDefaults
        var fileDescriptions: [String: String] = [:]
        if let data = UserDefaults.standard.data(forKey: "FileDescriptions"),
           let descriptions = try? JSONDecoder().decode([String: String].self, from: data) {
            fileDescriptions = descriptions
        }
        
        return MindConfig(
            version: exportVersion,
            exportDate: Date(),
            persona: persona,
            fileDescriptions: fileDescriptions
        )
    }
    
    private func restoreMindConfig(_ config: MindConfig) throws {
        // Restore persona settings to Keychain
        if let assistantName = config.persona.assistantName {
            try KeychainHelper.save(key: KeychainHelper.assistantNameKey, value: assistantName)
        }
        if let userName = config.persona.userName {
            try KeychainHelper.save(key: KeychainHelper.userNameKey, value: userName)
        }
        if let userContext = config.persona.userContext {
            try KeychainHelper.save(key: KeychainHelper.userContextKey, value: userContext)
        }
        if let structuredUserContext = config.persona.structuredUserContext {
            try KeychainHelper.save(key: KeychainHelper.structuredUserContextKey, value: structuredUserContext)
        }
        
        // Restore file descriptions to UserDefaults
        if !config.fileDescriptions.isEmpty {
            if let data = try? JSONEncoder().encode(config.fileDescriptions) {
                UserDefaults.standard.set(data, forKey: "FileDescriptions")
            }
        }
    }
}

// MARK: - Errors

enum MindExportError: LocalizedError {
    case zipFailed(String)
    case unzipFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .zipFailed(let message):
            return "Failed to create archive: \(message)"
        case .unzipFailed(let message):
            return "Failed to extract archive: \(message)"
        }
    }
}
