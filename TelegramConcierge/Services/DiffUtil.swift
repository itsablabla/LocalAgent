import Foundation

/// Unified-diff helper for write_file / edit_file / apply_patch results.
/// Shells out to /usr/bin/diff (always present on macOS) to produce a
/// standard unified-diff payload. The diff goes into the *current turn's*
/// tool result only — it never enters the cached system-prompt prefix, so
/// there is no prompt-cache impact. Context management (pruning old tool
/// interactions) keeps the overall context budget in check.
enum DiffUtil {

    /// Return a unified diff of `old` → `new`, or nil if diff is empty / the
    /// subprocess fails. The caller should treat nil as "no diff to show".
    ///
    /// - Parameters:
    ///   - old: pre-image text. Pass "" when creating a new file.
    ///   - new: post-image text.
    ///   - path: absolute path of the file — used only in the diff headers
    ///     (`--- a/<path>` / `+++ b/<path>`) so the model sees a meaningful
    ///     location instead of a tmpfile path.
    ///   - context: number of context lines around each hunk (default 3).
    static func unifiedDiff(
        old: String,
        new: String,
        path: String,
        context: Int = 3
    ) -> String? {
        if old == new { return nil }

        let tmpDir = FileManager.default.temporaryDirectory
        let stamp = UUID().uuidString.prefix(8)
        let oldURL = tmpDir.appendingPathComponent("localagent-diff-\(stamp).old")
        let newURL = tmpDir.appendingPathComponent("localagent-diff-\(stamp).new")
        defer {
            try? FileManager.default.removeItem(at: oldURL)
            try? FileManager.default.removeItem(at: newURL)
        }
        do {
            try (old.data(using: .utf8) ?? Data()).write(to: oldURL, options: .atomic)
            try (new.data(using: .utf8) ?? Data()).write(to: newURL, options: .atomic)
        } catch {
            return nil
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        proc.arguments = ["-u", "-U", String(context), oldURL.path, newURL.path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            return nil
        }
        proc.waitUntilExit()
        // `diff` exits 0 when identical, 1 when different, 2 on trouble.
        guard proc.terminationStatus == 1 else { return nil }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard var text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return nil
        }

        // Replace tmpfile paths in the two header lines with the real path.
        text = text.replacingOccurrences(of: oldURL.path, with: "a/" + path)
        text = text.replacingOccurrences(of: newURL.path, with: "b/" + path)

        return text
    }
}
