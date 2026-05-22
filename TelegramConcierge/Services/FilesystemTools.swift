import Foundation
import UniformTypeIdentifiers
import PDFKit
import AppKit
import ImageIO

/// Core filesystem tool implementations: read_file, write_file, edit_file.
/// Apply_patch lives in its own file (`ApplyPatch.swift`).
///
/// All methods take an absolute path (never relative, never ~-expanded by tilde alone —
/// the caller should pass the already-expanded path). These return plain result shapes;
/// the ToolExecutor wraps them into ToolResultMessage when dispatching.
actor FilesystemTools {
    static let shared = FilesystemTools()

    // Caps — mirror Claude Code's Read tool.
    static let maxLines = 2000
    static let maxBytes = 256 * 1024         // 256 KB cap for text output (matches Claude Code)
    static let maxLineLength = 2000          // truncate lines longer than this
    static let maxTokens = 25_000            // token cap for text reads (matches Claude Code)

    // Image caps — mirror Claude Code's auto-downscale behavior.
    static let imageMaxLongSide = 1568        // Anthropic's internal resize cap
    static let imageMaxTokens = 5_000         // token budget per image read
    static let imageDownscaleQuality: CGFloat = 0.80  // JPEG quality for resized images

    struct ReadResult {
        let content: String
        let attachments: [FileAttachment]
    }

    struct OpResult {
        let content: String
    }

    private init() {}

    // MARK: - read_file

    // PDF containment (matches Claude Code's Read tool).
    static let pdfPagesRequiredThreshold = 10
    static let pdfMaxPagesPerCall = 20

    /// Read a text file (paginated) OR load an image/PDF as a FileAttachment for
    /// multimodal injection. Always snapshots FileTime on success.
    /// `pages` (for PDFs only): range string like "1-5", "3", or "10-20". Required when the
    /// PDF has more than 10 pages; capped at 20 pages per call.
    func readFile(path rawPath: String, offset: Int? = nil, limit: Int? = nil, pages: String? = nil) async -> ReadResult {
        let path = Self.normalizePath(rawPath)

        guard Self.isAbsolute(path) else {
            return ReadResult(content: jsonError("path must be absolute (start with '/' or '~')"), attachments: [])
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return ReadResult(content: jsonError("file not found: \(path)"), attachments: [])
        }
        if isDir.boolValue {
            return ReadResult(content: jsonError("path is a directory, not a file. Use list_dir instead: \(path)"), attachments: [])
        }

        let mime = Self.mimeType(forPath: path)

        // Images → multimodal attachment, auto-downscaled if needed.
        if mime.hasPrefix("image/") && mime != "image/svg+xml" {
            do {
                var data = try Data(contentsOf: URL(fileURLWithPath: path))
                let filename = (path as NSString).lastPathComponent
                let originalBytes = data.count
                var finalMime = mime
                var wasResized = false

                // Check dimensions via ImageIO (cheap — no full decode).
                if let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                   let w = props[kCGImagePropertyPixelWidth] as? Int,
                   let h = props[kCGImagePropertyPixelHeight] as? Int {

                    let estimatedTokens = (w * h) / 750
                    let longSide = max(w, h)

                    if estimatedTokens > Self.imageMaxTokens || longSide > Self.imageMaxLongSide {
                        // Downscale: fit within imageMaxLongSide, re-encode as JPEG.
                        let scale = Double(Self.imageMaxLongSide) / Double(longSide)
                        let newW = Int(Double(w) * scale)
                        let newH = Int(Double(h) * scale)

                        if let nsImage = NSImage(data: data),
                           let resized = Self.resizeImage(nsImage, to: NSSize(width: newW, height: newH)) {
                            data = resized
                            finalMime = "image/jpeg"
                            wasResized = true
                        }
                    }
                }

                await FileTimeTracker.shared.recordRead(path: path)
                let attachment = FileAttachment(data: data, mimeType: finalMime, filename: filename, sourcePath: path)
                var summary: [String: Any] = [
                    "success": true,
                    "path": path,
                    "mime_type": finalMime,
                    "size_bytes": data.count,
                    "message": "Image attached. It will be visible to you on the next turn as a user-role multimodal message."
                ]
                if wasResized {
                    summary["resized"] = true
                    summary["original_size_bytes"] = originalBytes
                    summary["message"] = "Image was auto-downscaled to fit within \(Self.imageMaxLongSide)px (token budget). Attached as JPEG."
                }
                return ReadResult(content: jsonString(summary), attachments: [attachment])
            } catch {
                return ReadResult(content: jsonError("failed to read \(path): \(error.localizedDescription)"), attachments: [])
            }
        }

        // PDFs → enforce page-range caps, slice if needed.
        if mime == "application/pdf" {
            return await Self.readPDF(path: path, pages: pages)
        }

        // Text path. Reject other binaries.
        if Self.looksBinary(mime: mime, path: path) {
            return ReadResult(content: jsonError("cannot read binary file \(path) (mime=\(mime)). Use bash tools if you need to inspect it."), attachments: [])
        }

        // E88-style hard ceiling: whole-file reads are capped at 256 KB (matches Claude Code's
        // Read tool). If the file exceeds that AND the caller didn't request a slice, refuse
        // with the same wording Claude Code emits — the agent must paginate via offset/limit
        // or search for specific content instead.
        if offset == nil && limit == nil,
           let attrs = try? fm.attributesOfItem(atPath: path),
           let fileSize = attrs[.size] as? Int,
           fileSize > Self.maxBytes {
            let sizeKB = Double(fileSize) / 1024.0
            let msg = String(
                format: "File content (%.1fKB) exceeds maximum allowed size (256KB). Use offset and limit parameters to read specific portions of the file, or search for specific content instead of reading the whole file.",
                sizeKB
            )
            return ReadResult(content: jsonError(msg), attachments: [])
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return ReadResult(content: jsonError("file \(path) is not valid UTF-8 or Latin-1 text"), attachments: [])
            }
            await FileTimeTracker.shared.recordRead(path: path)

            let allLines = text.components(separatedBy: "\n")
            let startLine = max((offset ?? 1) - 1, 0)           // offset is 1-indexed
            if startLine >= allLines.count {
                return ReadResult(
                    content: jsonString([
                        "success": true,
                        "path": path,
                        "total_lines": allLines.count,
                        "returned_lines": 0,
                        "offset": offset ?? 1,
                        "truncated": false,
                        "content": "",
                        "message": "offset \(offset ?? 1) exceeds file length (\(allLines.count) lines)"
                    ]),
                    attachments: []
                )
            }
            let effectiveLimit = limit ?? Self.maxLines
            let endLine = min(startLine + effectiveLimit, allLines.count)
            var slice = Array(allLines[startLine..<endLine])
            var truncatedLongLines = 0
            for i in slice.indices {
                if slice[i].count > Self.maxLineLength {
                    slice[i] = String(slice[i].prefix(Self.maxLineLength)) + "… [line truncated at \(Self.maxLineLength) chars]"
                    truncatedLongLines += 1
                }
            }
            // Prepend 1-indexed line numbers so the agent can reference exact lines
            // when editing. Format: right-aligned to the width of the last line number, then "→".
            // Example: "  42→let x = 1".
            let lastLineNumber = startLine + slice.count
            let numWidth = String(lastLineNumber).count
            for i in slice.indices {
                let n = startLine + i + 1
                let padded = String(repeating: " ", count: max(0, numWidth - String(n).count)) + String(n)
                slice[i] = "\(padded)→\(slice[i])"
            }
            var joined = slice.joined(separator: "\n")
            var bytesTruncated = false
            if joined.utf8.count > Self.maxBytes {
                // Trim from the end to fit the byte cap.
                let utf8Bytes = Array(joined.utf8)
                let clipped = utf8Bytes.prefix(Self.maxBytes)
                joined = String(bytes: clipped, encoding: .utf8) ?? joined
                joined += "\n… [output capped at \(Self.maxBytes) bytes]"
                bytesTruncated = true
            }

            // Token cap (matches Claude Code): reject if content exceeds 25K tokens.
            // Only enforced for whole-file reads (no explicit limit) to match CC behavior.
            let estimatedTokens = joined.utf8.count / 4
            if limit == nil && estimatedTokens > Self.maxTokens {
                let msg = "File content (~\(estimatedTokens) tokens) exceeds maximum allowed tokens (\(Self.maxTokens)). Use offset and limit parameters to read specific portions of the file, or use grep to search for specific content instead of reading the whole file."
                return ReadResult(content: jsonError(msg), attachments: [])
            }

            let truncated = endLine < allLines.count || bytesTruncated
            var result: [String: Any] = [
                "success": true,
                "path": path,
                "total_lines": allLines.count,
                "returned_lines": endLine - startLine,
                "offset": startLine + 1,
                "truncated": truncated,
                "content": joined
            ]
            if truncated {
                result["message"] = "File truncated. Returned lines \(startLine + 1)..\(endLine) of \(allLines.count). Call read_file again with offset=\(endLine + 1) for more."
            }
            if truncatedLongLines > 0 {
                result["long_lines_truncated"] = truncatedLongLines
            }
            return ReadResult(content: jsonString(result), attachments: [])
        } catch {
            return ReadResult(content: jsonError("failed to read \(path): \(error.localizedDescription)"), attachments: [])
        }
    }

    // MARK: - write_file

    /// Create or overwrite a file. If the file exists, the agent must have read it this session;
    /// FileTime is asserted before write.
    func writeFile(path rawPath: String, content: String, description: String? = nil) async -> OpResult {
        let path = Self.normalizePath(rawPath)
        guard Self.isAbsolute(path) else {
            return OpResult(content: jsonError("path must be absolute: \(rawPath)"))
        }

        let fm = FileManager.default
        let fileExists = fm.fileExists(atPath: path)
        // Capture pre-image before overwriting so we can produce a unified
        // diff in the tool result.
        let previousContent: String?
        if fileExists {
            do {
                try await FileTimeTracker.shared.assertFresh(path: path)
            } catch {
                return OpResult(content: jsonError(error.localizedDescription))
            }
            previousContent = try? String(contentsOfFile: path, encoding: .utf8)
        } else {
            previousContent = nil
        }

        do {
            let url = URL(fileURLWithPath: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
            // Refresh FileTime snapshot so subsequent edits still pass the staleness check.
            await FileTimeTracker.shared.recordRead(path: path)
            let origin: FilesLedger.Origin = fileExists ? .edited : .generated
            await FilesLedger.shared.record(path: path, origin: origin, description: description)
            var result: [String: Any] = [
                "success": true,
                "path": path,
                "bytes_written": content.utf8.count,
                "operation": fileExists ? "overwrote" : "created"
            ]
            if let diff = DiffUtil.unifiedDiff(old: previousContent ?? "", new: content, path: path) {
                result["diff"] = diff
            }
            await LSPDiagnosticsReporter.attach(to: &result, path: path, updatedText: content)
            return OpResult(content: jsonString(result))
        } catch {
            return OpResult(content: jsonError("failed to write \(path): \(error.localizedDescription)"))
        }
    }

    // MARK: - edit_file

    /// Single-edit convenience wrapper — delegates to the batch method.
    func editFile(path rawPath: String, oldString: String, newString: String, replaceAll: Bool = false) async -> OpResult {
        return await editFile(path: rawPath, edits: [EditPair(oldString: oldString, newString: newString)], replaceAll: replaceAll)
    }

    /// A single old/new replacement pair.
    struct EditPair {
        let oldString: String
        let newString: String
    }

    /// Batch edit: apply one or more find/replace pairs atomically.
    /// All edits are matched against the ORIGINAL file content (not incrementally).
    /// If any edit fails validation, the file is untouched.
    /// Falls back through 3 match strategies per edit: literal → line-trimmed → whitespace-normalized.
    func editFile(path rawPath: String, edits: [EditPair], replaceAll: Bool = false) async -> OpResult {
        let path = Self.normalizePath(rawPath)
        guard Self.isAbsolute(path) else {
            return OpResult(content: jsonError("path must be absolute: \(rawPath)"))
        }
        guard !edits.isEmpty else {
            return OpResult(content: jsonError("edit_file requires at least one edit"))
        }
        for (i, edit) in edits.enumerated() {
            if edit.oldString.isEmpty {
                let label = edits.count > 1 ? "edits[\(i)]: " : ""
                return OpResult(content: jsonError("\(label)old_string must not be empty"))
            }
            if edit.oldString == edit.newString {
                let label = edits.count > 1 ? "edits[\(i)]: " : ""
                return OpResult(content: jsonError("\(label)old_string and new_string are identical — nothing to do"))
            }
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return OpResult(content: jsonError("file not found: \(path). Use write_file to create it."))
        }
        do {
            try await FileTimeTracker.shared.assertFresh(path: path)
        } catch {
            return OpResult(content: jsonError(error.localizedDescription))
        }

        guard let original = try? String(contentsOfFile: path, encoding: .utf8) else {
            return OpResult(content: jsonError("file \(path) is not valid UTF-8 text"))
        }

        // --- Phase 1: Match all edits against the ORIGINAL content ---
        struct MatchedEdit {
            let index: Int
            let range: Range<String.Index>
            let newString: String
            let strategy: String
        }

        var matchedEdits: [MatchedEdit] = []
        var usedNonLiteral = false

        for (i, edit) in edits.enumerated() {
            let label = edits.count > 1 ? "edits[\(i)]: " : ""

            switch EditStrategies.findMatches(source: original, oldString: edit.oldString, replaceAll: replaceAll) {
            case .noMatch:
                return OpResult(content: jsonError("\(label)old_string not found in \(path). It must match exactly including whitespace and indentation."))
            case .multipleMatches(let count):
                return OpResult(content: jsonError("\(label)old_string occurs \(count) times in \(path). Provide more surrounding context to make it unique, or pass replace_all=true."))
            case .success(let matches, let strategy):
                if strategy != "literal" { usedNonLiteral = true }

                for match in matches {
                    matchedEdits.append(MatchedEdit(
                        index: i,
                        range: match.range,
                        newString: edit.newString,
                        strategy: strategy
                    ))
                }
            }
        }

        // --- Phase 2: Check for overlaps ---
        let sorted = matchedEdits.sorted { $0.range.lowerBound < $1.range.lowerBound }
        for j in 1..<sorted.count {
            let prev = sorted[j - 1]
            let curr = sorted[j]
            if prev.range.upperBound > curr.range.lowerBound {
                return OpResult(content: jsonError("edits[\(prev.index)] and edits[\(curr.index)] overlap. Merge them into one edit or target disjoint regions."))
            }
        }

        // --- Phase 3: Apply all edits (last-to-first to keep positions stable) ---
        var updated = original
        let sortedReversed = matchedEdits.sorted { $0.range.lowerBound > $1.range.lowerBound }
        for m in sortedReversed {
            updated.replaceSubrange(m.range, with: m.newString)
        }

        if updated == original {
            return OpResult(content: jsonError("No changes made. The replacement produced identical content."))
        }

        // --- Phase 4: Write and report ---
        do {
            try updated.data(using: .utf8)?.write(to: URL(fileURLWithPath: path), options: .atomic)
            await FileTimeTracker.shared.recordRead(path: path)
            await FilesLedger.shared.record(path: path, origin: .edited, description: nil)
            var result: [String: Any] = [
                "success": true,
                "path": path,
                "edits_applied": matchedEdits.count,
                "bytes_written": updated.utf8.count
            ]
            if let diff = DiffUtil.unifiedDiff(old: original, new: updated, path: path) {
                result["diff"] = diff
            }
            if usedNonLiteral {
                result["match_strategy_warning"] = "One or more edits applied using fuzzy matching. Inspect the diff carefully."
            }
            await LSPDiagnosticsReporter.attach(to: &result, path: path, updatedText: updated)
            return OpResult(content: jsonString(result))
        } catch {
            return OpResult(content: jsonError("failed to write \(path): \(error.localizedDescription)"))
        }
    }

    // MARK: - Helpers

    static func normalizePath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~") {
            return (trimmed as NSString).expandingTildeInPath
        }
        return trimmed
    }

    static func isAbsolute(_ path: String) -> Bool {
        path.hasPrefix("/")
    }

    static func mimeType(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext.isEmpty { return "application/octet-stream" }
        if let uti = UTType(filenameExtension: ext), let mime = uti.preferredMIMEType {
            return mime
        }
        // Fallback table for common types.
        switch ext {
        case "txt", "md", "log": return "text/plain"
        case "swift": return "text/x-swift"
        case "py": return "text/x-python"
        case "js", "mjs", "cjs": return "text/javascript"
        case "ts", "tsx": return "text/typescript"
        case "json": return "application/json"
        case "yaml", "yml": return "application/yaml"
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "xml": return "application/xml"
        default: return "application/octet-stream"
        }
    }

    static func isMultimodalMime(_ mime: String) -> Bool {
        mime.hasPrefix("image/") && mime != "image/svg+xml"
            || mime == "application/pdf"
    }

    // MARK: - PDF page-range handling (parity with Claude Code Read)

    /// Load a PDF, optionally slice to a page range, and return a FileAttachment.
    /// - PDFs with <= `pdfPagesRequiredThreshold` pages: returned whole when `pages` is omitted.
    /// - PDFs with more pages: `pages` is REQUIRED. Missing → error telling the agent the page count
    ///   and requiring a range.
    /// - `pages` always capped at `pdfMaxPagesPerCall` pages per call.
    static func readPDF(path: String, pages: String?) async -> ReadResult {
        func err(_ msg: String) -> ReadResult {
            ReadResult(content: "{\"error\": \(jsonLiteral(msg))}", attachments: [])
        }
        guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
            return err("failed to open PDF: \(path)")
        }
        let totalPages = doc.pageCount
        guard totalPages > 0 else {
            return err("PDF \(path) has zero pages.")
        }

        // Determine which pages to include.
        let requestedRange: ClosedRange<Int>
        if let p = pages?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            guard let parsed = parsePageRange(p, totalPages: totalPages) else {
                return err("invalid pages value '\(p)'. Use formats like '3', '1-5', or '10-20'. PDF has \(totalPages) pages.")
            }
            requestedRange = parsed
        } else if totalPages > pdfPagesRequiredThreshold {
            return err("PDF \(path) has \(totalPages) pages — too large to read in one call. Specify a page range via the 'pages' parameter (e.g. pages=\"1-5\" or pages=\"10-20\"). Max \(pdfMaxPagesPerCall) pages per call.")
        } else {
            requestedRange = 1...totalPages
        }

        let spanned = requestedRange.upperBound - requestedRange.lowerBound + 1
        guard spanned <= pdfMaxPagesPerCall else {
            return err("page range '\(pages ?? "")' spans \(spanned) pages. Max \(pdfMaxPagesPerCall) pages per call.")
        }

        // Build a sliced PDF containing only the requested pages.
        let slicedData: Data
        let slicedPageCount: Int
        if requestedRange.lowerBound == 1 && requestedRange.upperBound == totalPages {
            // Whole document — return the original bytes.
            do {
                slicedData = try Data(contentsOf: URL(fileURLWithPath: path))
                slicedPageCount = totalPages
            } catch {
                return err("failed to load PDF bytes: \(error.localizedDescription)")
            }
        } else {
            let sliced = PDFDocument()
            var idx = 0
            for pageNum in requestedRange {
                // PDFKit uses 0-indexed page numbers.
                if let page = doc.page(at: pageNum - 1) {
                    sliced.insert(page, at: idx)
                    idx += 1
                }
            }
            guard let data = sliced.dataRepresentation() else {
                return err("failed to serialize sliced PDF for range \(requestedRange.lowerBound)-\(requestedRange.upperBound).")
            }
            slicedData = data
            slicedPageCount = idx
        }

        await FileTimeTracker.shared.recordRead(path: path)
        let filename = (path as NSString).lastPathComponent
        let pageRange = "\(requestedRange.lowerBound)-\(requestedRange.upperBound)"
        let attachment = FileAttachment(data: slicedData, mimeType: "application/pdf", filename: filename, sourcePath: path, pageRange: pageRange)
        let summary: [String: Any] = [
            "success": true,
            "path": path,
            "mime_type": "application/pdf",
            "total_pages": totalPages,
            "pages_returned": slicedPageCount,
            "page_range": pageRange,
            "size_bytes": slicedData.count,
            "message": "PDF pages \(requestedRange.lowerBound)–\(requestedRange.upperBound) of \(totalPages) attached. They will be visible to you on the next turn as a user-role multimodal message."
        ]
        return ReadResult(content: jsonStringStatic(summary), attachments: [attachment])
    }

    /// Parse "3", "1-5", "10-20" → ClosedRange<Int> clamped to [1, totalPages].
    /// Returns nil on malformed input or ranges outside [1, totalPages].
    static func parsePageRange(_ raw: String, totalPages: Int) -> ClosedRange<Int>? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if let single = Int(s) {
            guard single >= 1, single <= totalPages else { return nil }
            return single...single
        }
        let parts = s.split(separator: "-", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lo = Int(parts[0]), let hi = Int(parts[1]) else { return nil }
        guard lo >= 1, hi >= lo, lo <= totalPages else { return nil }
        let clampedHi = min(hi, totalPages)
        return lo...clampedHi
    }

    private static func jsonLiteral(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [s], options: []),
           let str = String(data: data, encoding: .utf8) {
            // Strip the surrounding brackets to get just the quoted+escaped string.
            let trimmed = str.dropFirst().dropLast()
            return String(trimmed)
        }
        return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func jsonStringStatic(_ dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\"error\": \"failed to encode response\"}"
    }

    /// Heuristic: if mime is known text-ish, treat as text. Otherwise check for null bytes.
    static func looksBinary(mime: String, path: String) -> Bool {
        if mime.hasPrefix("text/") { return false }
        if mime == "application/json"
            || mime == "application/yaml"
            || mime == "application/xml"
            || mime == "application/javascript"
            || mime == "image/svg+xml" { return false }
        // Sample first 4KB for null bytes.
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return true }
        defer { try? handle.close() }
        let sample = (try? handle.read(upToCount: 4096)) ?? Data()
        return sample.contains(0)
    }

    private func jsonError(_ message: String) -> String {
        jsonString(["error": message])
    }

    private func jsonString(_ dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\"error\": \"failed to encode response\"}"
    }

    // MARK: - Image downscaling

    /// Resize an NSImage to the target size and encode as JPEG.
    /// Returns nil on failure (caller falls back to the original data).
    private static func resizeImage(_ image: NSImage, to targetSize: NSSize) -> Data? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        guard let tiffData = newImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: imageDownscaleQuality]
              ) else {
            return nil
        }
        return jpegData
    }
}

// MARK: - Edit match strategies

enum EditStrategies {
    enum MatchOutcome {
        case noMatch
        case multipleMatches(count: Int)
        case success(matches: [MatchRange], strategy: String)
    }

    struct MatchRange {
        let range: Range<String.Index>
    }

    private struct SourceLine {
        let text: String
        let range: Range<String.Index>
    }

    /// Find exact source ranges for oldString without building a replacement string.
    static func findMatches(source: String, oldString: String, replaceAll: Bool) -> MatchOutcome {
        let literalRanges = rangesOf(needle: oldString, inHaystack: source)
        if !literalRanges.isEmpty {
            if literalRanges.count > 1 && !replaceAll {
                return .multipleMatches(count: literalRanges.count)
            }
            return .success(matches: literalRanges.map { MatchRange(range: $0) }, strategy: "literal")
        }

        let sourceLines = linesWithRanges(in: source)
        if let ranges = findLineTrimmedRanges(sourceLines: sourceLines, oldString: oldString) {
            if ranges.count > 1 && !replaceAll {
                return .multipleMatches(count: ranges.count)
            }
            return .success(matches: ranges.map { MatchRange(range: $0) }, strategy: "line-trimmed")
        }

        if let ranges = findWhitespaceNormalizedRanges(sourceLines: sourceLines, oldString: oldString) {
            if ranges.count > 1 && !replaceAll {
                return .multipleMatches(count: ranges.count)
            }
            return .success(matches: ranges.map { MatchRange(range: $0) }, strategy: "whitespace-normalized")
        }

        return .noMatch
    }

    private static func linesWithRanges(in source: String) -> [SourceLine] {
        var lines: [SourceLine] = []
        var lineStart = source.startIndex
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == "\n" {
                lines.append(SourceLine(text: String(source[lineStart..<index]), range: lineStart..<index))
                index = source.index(after: index)
                lineStart = index
            } else {
                index = source.index(after: index)
            }
        }

        lines.append(SourceLine(text: String(source[lineStart..<source.endIndex]), range: lineStart..<source.endIndex))
        return lines
    }

    private static func findLineTrimmedRanges(sourceLines: [SourceLine], oldString: String) -> [Range<String.Index>]? {
        let oldLines = oldString
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }
        guard !oldLines.isEmpty, oldLines.count <= sourceLines.count else { return nil }

        var ranges: [Range<String.Index>] = []
        for start in 0...(sourceLines.count - oldLines.count) {
            var hit = true
            for i in 0..<oldLines.count {
                let srcLine = sourceLines[start + i].text.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                if srcLine != oldLines[i] { hit = false; break }
            }
            if hit {
                ranges.append(sourceLines[start].range.lowerBound..<sourceLines[start + oldLines.count - 1].range.upperBound)
            }
        }
        return ranges.isEmpty ? nil : ranges
    }

    private static func findWhitespaceNormalizedRanges(sourceLines: [SourceLine], oldString: String) -> [Range<String.Index>]? {
        func normalize(_ s: String) -> String {
            let collapsed = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            return collapsed.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }
                .joined(separator: "\n")
        }

        let normalizedOld = normalize(oldString)
        let oldLineCount = oldString.components(separatedBy: "\n").count
        guard oldLineCount > 0, oldLineCount <= sourceLines.count else { return nil }

        var ranges: [Range<String.Index>] = []
        for start in 0...(sourceLines.count - oldLineCount) {
            let window = sourceLines[start..<(start + oldLineCount)].map(\.text).joined(separator: "\n")
            if normalize(window) == normalizedOld {
                ranges.append(sourceLines[start].range.lowerBound..<sourceLines[start + oldLineCount - 1].range.upperBound)
            }
        }
        return ranges.isEmpty ? nil : ranges
    }

    private static func rangesOf(needle: String, inHaystack haystack: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        guard !needle.isEmpty else { return ranges }
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}
