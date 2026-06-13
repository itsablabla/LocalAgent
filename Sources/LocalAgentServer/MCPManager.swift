import Foundation

actor MCPManager {
    private var clients: [String: MCPClient] = [:]

    func connect(servers: [MCPServerConfig]) async {
        await withTaskGroup(of: Void.self) { group in
            for cfg in servers {
                group.addTask {
                    let client = MCPClient(config: cfg)
                    do {
                        try await client.connect()
                        await self.register(cfg.name, client)
                    } catch {
                        print("[MCP] \(cfg.name) failed to connect: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func register(_ name: String, _ client: MCPClient) {
        clients[name] = client
    }

    func allTools() async -> [ToolDefinition] {
        var out: [ToolDefinition] = []
        for client in clients.values {
            out += await client.tools
        }
        return out
    }

    func isMCPTool(_ name: String) -> Bool {
        clients.keys.contains { name.hasPrefix($0 + "__") }
    }

    func callTool(prefixedName: String, arguments: String) async throws -> String {
        let parts = prefixedName.components(separatedBy: "__")
        guard parts.count >= 2 else {
            throw MCPError.toolError("bad tool name: \(prefixedName)")
        }
        let serverName = parts[0]
        let toolName = parts.dropFirst().joined(separator: "__")
        guard let client = clients[serverName] else {
            throw MCPError.toolError("no MCP server '\(serverName)'")
        }
        return try await client.callTool(name: toolName, arguments: arguments)
    }
}
