import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Tool definitions

let agentTools: [ToolDefinition] = [
    ToolDefinition(type: "function", function: FunctionDefinition(
        name: "bash",
        description: "Execute a shell command and return stdout+stderr. Use for running scripts, installing packages, checking system state, or any CLI task.",
        parameters: JSONSchema(type: "object", properties: [
            "command": PropertySchema(type: "string", description: "Shell command to execute"),
            "timeout": PropertySchema(type: "string", description: "Optional timeout in seconds (default 30)")
        ], required: ["command"])
    )),
    ToolDefinition(type: "function", function: FunctionDefinition(
        name: "read_file",
        description: "Read the contents of a file at the given path.",
        parameters: JSONSchema(type: "object", properties: [
            "path": PropertySchema(type: "string", description: "Absolute or relative file path")
        ], required: ["path"])
    )),
    ToolDefinition(type: "function", function: FunctionDefinition(
        name: "write_file",
        description: "Write content to a file, creating parent directories if needed.",
        parameters: JSONSchema(type: "object", properties: [
            "path": PropertySchema(type: "string", description: "File path to write"),
            "content": PropertySchema(type: "string", description: "Content to write")
        ], required: ["path", "content"])
    )),
    ToolDefinition(type: "function", function: FunctionDefinition(
        name: "list_dir",
        description: "List the contents of a directory.",
        parameters: JSONSchema(type: "object", properties: [
            "path": PropertySchema(type: "string", description: "Directory path (defaults to current directory)")
        ], required: [])
    )),
    ToolDefinition(type: "function", function: FunctionDefinition(
        name: "web_fetch",
        description: "Fetch the content of a URL and return it as text.",
        parameters: JSONSchema(type: "object", properties: [
            "url": PropertySchema(type: "string", description: "URL to fetch")
        ], required: ["url"])
    )),
    ToolDefinition(type: "function", function: FunctionDefinition(
        name: "grep",
        description: "Search for a pattern in files using grep.",
        parameters: JSONSchema(type: "object", properties: [
            "pattern": PropertySchema(type: "string", description: "Search pattern (supports regex)"),
            "path": PropertySchema(type: "string", description: "File or directory to search")
        ], required: ["pattern", "path"])
    ))
]

// MARK: - Tool executor

struct ToolExecutor {
    let workDir: String

    func execute(name: String, arguments: String) async -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] else {
            return "Error: invalid JSON arguments"
        }

        switch name {
        case "bash":
            return await runBash(args: args)
        case "read_file":
            return readFile(args: args)
        case "write_file":
            return writeFile(args: args)
        case "list_dir":
            return listDir(args: args)
        case "web_fetch":
            return await webFetch(args: args)
        case "grep":
            return await runGrep(args: args)
        default:
            return "Error: unknown tool \(name)"
        }
    }

    private func runBash(args: [String: Any]) async -> String {
        guard let command = args["command"] as? String else {
            return "Error: missing 'command'"
        }
        let timeout = (args["timeout"] as? String).flatMap(Double.init) ?? 30.0

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            var output = ""
            var timedOut = false

            let timer = DispatchWorkItem {
                if process.isRunning {
                    timedOut = true
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

            do {
                try process.run()
                process.waitUntilExit()
                timer.cancel()

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""

                if timedOut {
                    output = "Error: command timed out after \(Int(timeout))s\n\(stdout)\(stderr)"
                } else if !stderr.isEmpty && stdout.isEmpty {
                    output = stderr
                } else if !stderr.isEmpty {
                    output = stdout + "\n[stderr]: " + stderr
                } else {
                    output = stdout.isEmpty ? "(no output, exit code \(process.terminationStatus))" : stdout
                }
            } catch {
                output = "Error: \(error.localizedDescription)"
            }

            // Truncate very long output
            if output.count > 8000 {
                output = String(output.prefix(7900)) + "\n...[truncated]"
            }

            continuation.resume(returning: output)
        }
    }

    private func readFile(args: [String: Any]) -> String {
        guard let path = args["path"] as? String else {
            return "Error: missing 'path'"
        }
        let url = resolvedURL(path)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Error: could not read file at \(path)"
        }
        if content.count > 20000 {
            return String(content.prefix(20000)) + "\n...[truncated at 20000 chars]"
        }
        return content
    }

    private func writeFile(args: [String: Any]) -> String {
        guard let path = args["path"] as? String,
              let content = args["content"] as? String else {
            return "Error: missing 'path' or 'content'"
        }
        let url = resolvedURL(path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "Wrote \(content.count) chars to \(path)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func listDir(args: [String: Any]) -> String {
        let path = (args["path"] as? String) ?? workDir
        let url = resolvedURL(path)
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            let lines = items.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { u -> String in
                let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return isDir ? "\(u.lastPathComponent)/" : u.lastPathComponent
            }
            return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func webFetch(args: [String: Any]) async -> String {
        guard let urlStr = args["url"] as? String,
              let url = URL(string: urlStr) else {
            return "Error: missing or invalid 'url'"
        }
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 LocalAgentServer/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30
            let (data, _) = try await URLSession.shared.fetchData(for: request)
            var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? "(binary)"
            // Strip HTML tags for readability
            text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: String.CompareOptions.regularExpression)
            text = text.replacingOccurrences(of: "\\s{3,}", with: "\n\n", options: String.CompareOptions.regularExpression)
            if text.count > 12000 {
                text = String(text.prefix(12000)) + "\n...[truncated]"
            }
            return text
        } catch {
            return "Error fetching \(urlStr): \(error.localizedDescription)"
        }
    }

    private func runGrep(args: [String: Any]) async -> String {
        guard let pattern = args["pattern"] as? String,
              let path = args["path"] as? String else {
            return "Error: missing 'pattern' or 'path'"
        }
        return await runBash(args: ["command": "grep -rn \(shellEscape(pattern)) \(shellEscape(path)) 2>&1 | head -100"])
    }

    private func resolvedURL(_ path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: workDir).appendingPathComponent(path)
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
