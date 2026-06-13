import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct MCPServerConfig {
    let name: String
    let sseURL: String
    let token: String?
    let extraHeaders: [String: String]
    let transport: String  // "sse" (default) or "http"
}

actor MCPClient {
    let config: MCPServerConfig
    private var sessionPostURL: String?
    private var process: Process?
    private var sseBuffer = ""
    private var waiters: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextId = 1
    private(set) var tools: [ToolDefinition] = []

    init(config: MCPServerConfig) {
        self.config = config
    }

    func connect() async throws {
        if config.transport == "http" {
            try await connectHTTP()
        } else {
            try await connectSSE()
        }
    }

    // MARK: - HTTP (Streamable HTTP) transport

    private func connectHTTP() async throws {
        sessionPostURL = config.sseURL

        _ = try await httpRpc("initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "LocalAgentServer", "version": "1.0"] as [String: Any]
        ], timeoutSeconds: 15)

        try await postHTTP(["jsonrpc": "2.0", "method": "notifications/initialized", "params": [:] as [String: Any]])

        let resp = try await httpRpc("tools/list", params: [:], timeoutSeconds: 15)
        if let result = resp["result"] as? [String: Any],
           let arr = result["tools"] as? [[String: Any]] {
            self.tools = arr.prefix(60).compactMap { parseTool($0) }
            print("[\(config.name)] \(self.tools.count) tools loaded (http)")
        }
    }

    private func httpRpc(_ method: String, params: [String: Any], timeoutSeconds: Double = 90) async throws -> [String: Any] {
        guard let urlStr = sessionPostURL, let url = URL(string: urlStr) else {
            throw MCPError.connectionFailed("no URL for \(config.name)")
        }
        let id = nextId; nextId += 1
        let body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params, "id": id]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let tok = config.token {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in config.extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = timeoutSeconds

        let (data, response) = try await URLSession.shared.fetchData(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MCPError.connectionFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(body.prefix(200))")
        }

        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("text/event-stream") {
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.components(separatedBy: "\n") {
                if line.hasPrefix("data:") {
                    let jsonStr = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if let jd = jsonStr.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jd) as? [String: Any] {
                        return json
                    }
                }
            }
            throw MCPError.connectionFailed("no JSON in SSE response from \(config.name)")
        } else {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MCPError.connectionFailed("invalid JSON from \(config.name)")
            }
            return json
        }
    }

    private func postHTTP(_ body: [String: Any]) async throws {
        guard let urlStr = sessionPostURL, let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let tok = config.token {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in config.extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10
        _ = try? await URLSession.shared.fetchData(for: req)
    }

    // MARK: - SSE transport

    private func connectSSE() async throws {
        let proc = Process()
        let outPipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args = ["-N", "--no-buffer", "-s",
                    "-H", "Accept: text/event-stream",
                    "-H", "Cache-Control: no-cache"]
        if let tok = config.token {
            args += ["-H", "Authorization: Bearer \(tok)"]
        }
        for (k, v) in config.extraHeaders {
            args += ["-H", "\(k): \(v)"]
        }
        args.append(config.sseURL)
        proc.arguments = args
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        try proc.run()
        self.process = proc

        let handle = outPipe.fileHandleForReading
        let procCapture = proc
        Task.detached { [weak self] in
            while procCapture.isRunning {
                let data = handle.availableData
                if data.isEmpty {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    continue
                }
                if let text = String(data: data, encoding: .utf8) {
                    await self?.processSSE(text)
                }
            }
        }

        for _ in 0..<150 {
            if sessionPostURL != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard sessionPostURL != nil else {
            throw MCPError.connectionFailed("[\(config.name)] no endpoint in 15s — check URL/auth")
        }

        _ = try await rpc("initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "LocalAgentServer", "version": "1.0"] as [String: Any]
        ], timeoutSeconds: 15)
        try await post(["jsonrpc": "2.0", "method": "notifications/initialized", "params": [:] as [String: Any]])

        let resp = try await rpc("tools/list", params: [:], timeoutSeconds: 15)
        if let result = resp["result"] as? [String: Any],
           let arr = result["tools"] as? [[String: Any]] {
            self.tools = arr.prefix(60).compactMap { parseTool($0) }
            print("[\(config.name)] \(self.tools.count) tools loaded")
        }
    }

    private func processSSE(_ text: String) {
        sseBuffer += text
        while let range = sseBuffer.range(of: "\n\n") {
            let block = String(sseBuffer[..<range.lowerBound])
            sseBuffer = String(sseBuffer[range.upperBound...])
            parseBlock(block)
        }
    }

    private func parseBlock(_ block: String) {
        var event = ""
        var dataLines = [String]()
        for line in block.components(separatedBy: "\n") {
            if line.hasPrefix("event:") {
                event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        let data = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !data.isEmpty else { return }

        if event == "endpoint" || (sessionPostURL == nil && (data.hasPrefix("/") || data.hasPrefix("http"))) {
            if data.hasPrefix("http") {
                sessionPostURL = data
            } else if let base = URL(string: config.sseURL) {
                sessionPostURL = "\(base.scheme ?? "https")://\(base.host ?? "")\(base.port.map { ":\($0)" } ?? "")\(data)"
            }
            return
        }

        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let id = json["id"] as? Int,
              let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.resume(returning: json)
    }

    private func rpc(_ method: String, params: [String: Any], timeoutSeconds: Double = 90) async throws -> [String: Any] {
        let id = nextId; nextId += 1
        let body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params, "id": id]
        return try await withCheckedThrowingContinuation { cont in
            Task { [weak self] in
                guard let self else {
                    cont.resume(throwing: MCPError.connectionFailed("deallocated"))
                    return
                }
                await self.storeWaiter(id: id, cont: cont)
                do {
                    try await self.post(body)
                } catch {
                    let removed = await self.dropWaiter(id: id)
                    if removed { cont.resume(throwing: error) }
                }
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard let self else { return }
                let removed = await self.dropWaiter(id: id)
                if removed {
                    cont.resume(throwing: MCPError.toolError("timeout after \(Int(timeoutSeconds))s"))
                }
            }
        }
    }

    private func storeWaiter(id: Int, cont: CheckedContinuation<[String: Any], Error>) {
        waiters[id] = cont
    }

    private func dropWaiter(id: Int) -> Bool {
        return waiters.removeValue(forKey: id) != nil
    }

    private func post(_ body: [String: Any]) async throws {
        guard let urlStr = sessionPostURL, let url = URL(string: urlStr) else {
            throw MCPError.connectionFailed("no session URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let tok = config.token {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in config.extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60
        _ = try await URLSession.shared.fetchData(for: req)
    }

    func callTool(name: String, arguments: String) async throws -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any]) ?? [:]
        let resp: [String: Any]
        if config.transport == "http" {
            resp = try await httpRpc("tools/call", params: ["name": name, "arguments": args])
        } else {
            resp = try await rpc("tools/call", params: ["name": name, "arguments": args])
        }
        if let err = resp["error"] as? [String: Any] {
            throw MCPError.toolError(err["message"] as? String ?? "tool error")
        }
        guard let result = resp["result"] as? [String: Any] else { return "OK" }
        if let content = result["content"] as? [[String: Any]] {
            return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return (try? String(data: JSONSerialization.data(withJSONObject: result), encoding: .utf8)) ?? "OK"
    }

    private func parseTool(_ d: [String: Any]) -> ToolDefinition? {
        guard let rawName = d["name"] as? String else { return nil }
        let safeName = rawName.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let prefixed = "\(config.name)__\(safeName)"
        guard prefixed.count <= 64 else { return nil }
        let desc = (d["description"] as? String ?? safeName).prefix(120).description
        let schema = d["inputSchema"] as? [String: Any] ?? [:]
        let props = (schema["properties"] as? [String: [String: Any]] ?? [:]).compactMapValues { v -> PropertySchema? in
            PropertySchema(type: v["type"] as? String ?? "string", description: v["description"] as? String ?? "")
        }
        let req = schema["required"] as? [String] ?? []
        return ToolDefinition(
            type: "function",
            function: FunctionDefinition(
                name: prefixed,
                description: "[\(config.name)] \(desc)",
                parameters: JSONSchema(type: "object", properties: props, required: req)
            )
        )
    }
}

enum MCPError: Error, LocalizedError {
    case connectionFailed(String)
    case toolError(String)
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let m): return "MCP: \(m)"
        case .toolError(let m): return "MCP tool: \(m)"
        }
    }
}
