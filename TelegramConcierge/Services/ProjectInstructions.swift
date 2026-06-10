import Foundation

/// Auto-discovery and injection of per-project instruction files
/// (AGENTS.md / CLAUDE.md), the cross-tool standard for repo-level agent
/// guidance (build/test commands, conventions, gotchas).
///
/// When a tool touches a path inside a project, the nearest instruction file —
/// found by walking up from the touched path to the repository root — is
/// loaded once and appended to that tool's result, the same way LSP
/// diagnostics ride on edit results. Loaded state is tracked per executor
/// (the main agent and each subagent context inject independently), keyed by
/// instruction-file path + mtime so an edited file re-injects automatically.
///
/// Deliberately NOT protected from context pruning: when the watermark pruner
/// drops the tool interaction carrying the instructions, it clears the
/// corresponding entry here (see ConversationManager.applyPrunePlan), and the
/// next tool touching that project re-injects them. Projects being actively
/// worked on re-load within one tool call; dormant projects fall out of
/// context entirely, so nothing accumulates across weeks of conversation.
final class ProjectInstructionsTracker: @unchecked Sendable {

    /// Checked in order; the first match in a directory wins.
    static let instructionFileNames = ["AGENTS.md", "CLAUDE.md"]

    /// Cap on injected instruction content (~5k tokens).
    static let maxContentLength = 20_000

    static let markerPrefix = "[PROJECT INSTRUCTIONS: "
    static let markerEnd = "[END PROJECT INSTRUCTIONS]"

    /// Tools whose arguments carry filesystem paths worth scanning.
    private static let pathAwareTools: Set<String> = [
        "read_file", "write_file", "edit_file", "apply_patch",
        "grep", "glob", "list_dir", "bash", "lsp"
    ]

    private let lock = NSLock()
    /// Instruction-file path → mtime at the moment it was injected into this
    /// executor's context.
    private var loaded: [String: Date] = [:]

    // MARK: - Injection

    /// Returns a payload to append to the tool result when the touched project
    /// has an instruction file that is not yet in context (or has changed on
    /// disk since it was loaded). Returns nil when there is nothing new.
    func payload(toolName: String, argumentsJSON: String) -> String? {
        guard Self.pathAwareTools.contains(toolName) else { return nil }
        let touched = Self.touchedPaths(toolName: toolName, argumentsJSON: argumentsJSON)
        guard !touched.isEmpty else { return nil }

        let fm = FileManager.default
        var blocks: [String] = []
        var seenThisCall = Set<String>()

        for path in touched {
            guard let fileURL = Self.instructionFile(forTouchedPath: path) else { continue }
            let filePath = fileURL.path
            guard !seenThisCall.contains(filePath) else { continue }
            seenThisCall.insert(filePath)

            guard let mtime = (try? fm.attributesOfItem(atPath: filePath))?[.modificationDate] as? Date else { continue }

            lock.lock()
            let alreadyCurrent = loaded[filePath] == mtime
            if !alreadyCurrent { loaded[filePath] = mtime }
            lock.unlock()
            if alreadyCurrent { continue }

            // The model is reading the instruction file directly — record it
            // as loaded but don't duplicate its content in the same result.
            if toolName == "read_file",
               URL(fileURLWithPath: path).standardizedFileURL.path == filePath {
                continue
            }

            guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                lock.lock(); loaded.removeValue(forKey: filePath); lock.unlock()
                continue
            }
            if content.count > Self.maxContentLength {
                content = String(content.prefix(Self.maxContentLength))
                    + "\n…[truncated — read \(filePath) for the rest]"
            }
            let root = fileURL.deletingLastPathComponent().path
            blocks.append(
                Self.markerPrefix + filePath + "]\n"
                + "Project instruction file auto-loaded — follow it for all work under \(root):\n\n"
                + content.trimmingCharacters(in: .whitespacesAndNewlines)
                + "\n" + Self.markerEnd
            )
        }

        guard !blocks.isEmpty else { return nil }
        return "\n\n" + blocks.joined(separator: "\n\n")
    }

    /// Pruner callback: the tool interaction carrying this instruction file
    /// left the context, so the next touch of that project must re-inject.
    func clearLoaded(instructionFilePath: String) {
        lock.lock()
        loaded.removeValue(forKey: instructionFilePath)
        lock.unlock()
    }

    /// Scans a tool-result content string for injected instruction markers and
    /// returns the instruction-file paths it carried.
    static func markerPaths(in content: String) -> [String] {
        guard content.contains(markerPrefix) else { return [] }
        var paths: [String] = []
        var searchRange = content.startIndex..<content.endIndex
        while let prefixRange = content.range(of: markerPrefix, range: searchRange) {
            guard let closing = content.range(of: "]", range: prefixRange.upperBound..<content.endIndex) else { break }
            let path = String(content[prefixRange.upperBound..<closing.lowerBound])
            if path.hasPrefix("/") { paths.append(path) }
            searchRange = closing.upperBound..<content.endIndex
        }
        return paths
    }

    // MARK: - Discovery

    /// Walks up from a touched path looking for the nearest instruction file.
    /// Stops at the repository root (a directory containing .git) and never
    /// treats the home directory or filesystem root as a project.
    static func instructionFile(forTouchedPath path: String) -> URL? {
        let fm = FileManager.default
        let standardized = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL

        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: standardized.path, isDirectory: &isDir)
        var dir = (exists && isDir.boolValue) ? standardized : standardized.deletingLastPathComponent()

        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path

        for _ in 0..<64 {
            let dirPath = dir.path
            if dirPath == "/" || dirPath == home { break }

            for name in instructionFileNames {
                let candidate = dir.appendingPathComponent(name)
                var candidateIsDir: ObjCBool = false
                if fm.fileExists(atPath: candidate.path, isDirectory: &candidateIsDir), !candidateIsDir.boolValue {
                    return candidate
                }
            }

            // Repo root reached and no instruction file found anywhere below
            // it — don't escape into parent directories above the repo.
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { break }

            let parent = dir.deletingLastPathComponent()
            if parent.path == dirPath { break }
            dir = parent
        }
        return nil
    }

    /// Extracts candidate filesystem paths from a tool call's arguments.
    static func touchedPaths(toolName: String, argumentsJSON: String) -> [String] {
        guard let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var paths: [String] = []
        if toolName == "apply_patch" {
            if let patchText = obj["patch_text"] as? String {
                for line in patchText.split(separator: "\n", omittingEmptySubsequences: true) {
                    for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: ", "*** Move to: "] {
                        if line.hasPrefix(prefix) {
                            paths.append(String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
                            break
                        }
                    }
                }
            }
        } else if toolName == "bash" {
            if let workdir = obj["workdir"] as? String { paths.append(workdir) }
        } else {
            if let path = obj["path"] as? String { paths.append(path) }
        }

        return paths.filter { $0.hasPrefix("/") || $0.hasPrefix("~") }
    }
}
