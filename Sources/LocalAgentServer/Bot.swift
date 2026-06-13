import Foundation

actor Bot {
    private let config: Config
    private let telegram: TelegramClient
    private let openRouter: OpenRouterClient
    private let executor: ToolExecutor
    private let mcpManager = MCPManager()

    private var conversationHistory: [ChatMessage] = []
    private var mcpTools: [ToolDefinition] = []

    init(config: Config) {
        self.config = config
        self.telegram = TelegramClient(token: config.telegramBotToken)
        self.openRouter = OpenRouterClient(apiKey: config.openRouterApiKey, model: config.openRouterModel, baseURL: config.llmBaseUrl)
        self.executor = ToolExecutor(workDir: config.workDir)
    }

    func run() async {
        print("Bot started. Model: \(config.openRouterModel)")
        print("Listening for messages from chat \(config.telegramChatId)")

        if !config.mcpServers.isEmpty {
            print("Connecting to \(config.mcpServers.count) MCP server(s)…")
            await mcpManager.connect(servers: config.mcpServers)
            mcpTools = await mcpManager.allTools()
            print("MCP ready — \(mcpTools.count) additional tools")
        }

        while true {
            do {
                let updates = try await telegram.getUpdates()
                for update in updates {
                    guard let msg = update.message,
                          msg.chat.id == config.telegramChatId,
                          let text = msg.text,
                          !text.isEmpty else { continue }

                    await handleMessage(chatId: msg.chat.id, text: text)
                }
            } catch {
                print("Poll error: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func handleMessage(chatId: Int, text: String) async {
        try? await telegram.sendTyping(chatId: chatId)

        conversationHistory.append(ChatMessage(role: "user", text: text))

        do {
            let reply = try await runAgentLoop(chatId: chatId)
            try? await telegram.sendMessage(chatId: chatId, text: reply)
        } catch {
            let errMsg = "Error: \(error.localizedDescription)"
            print(errMsg)
            try? await telegram.sendMessage(chatId: chatId, text: errMsg)
        }
    }

    private func runAgentLoop(chatId: Int) async throws -> String {
        let maxIterations = 20
        var iterations = 0
        let allTools = agentTools + mcpTools

        while iterations < maxIterations {
            iterations += 1

            let response = try await openRouter.complete(
                systemPrompt: config.systemPrompt,
                messages: conversationHistory,
                tools: allTools
            )

            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                let assistantMsg = ChatMessage(
                    role: "assistant",
                    content: .text(response.content ?? ""),
                    toolCalls: toolCalls
                )
                conversationHistory.append(assistantMsg)

                if let thinking = response.content, !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try? await telegram.sendMessage(chatId: chatId, text: "💭 \(thinking)")
                }

                try? await telegram.sendTyping(chatId: chatId)

                for tc in toolCalls {
                    print("Tool call: \(tc.function.name)(\(tc.function.arguments.prefix(120)))")
                    let preview = toolCallPreview(name: tc.function.name, arguments: tc.function.arguments)
                    try? await telegram.sendMessage(chatId: chatId, text: preview)

                    let result: String
                    if await mcpManager.isMCPTool(tc.function.name) {
                        do {
                            result = try await mcpManager.callTool(prefixedName: tc.function.name, arguments: tc.function.arguments)
                        } catch {
                            result = "MCP error: \(error.localizedDescription)"
                        }
                    } else {
                        result = await executor.execute(name: tc.function.name, arguments: tc.function.arguments)
                    }

                    print("Result: \(result.prefix(120))")
                    conversationHistory.append(ChatMessage(
                        role: "tool",
                        content: .text(result),
                        toolCallId: tc.id
                    ))
                }

                try? await telegram.sendTyping(chatId: chatId)
                continue
            }

            let finalText = response.content ?? "(no response)"
            conversationHistory.append(ChatMessage(role: "assistant", text: finalText))

            if conversationHistory.count > 40 {
                conversationHistory = Array(conversationHistory.suffix(40))
            }

            return finalText
        }

        return "Reached maximum tool iterations (\(maxIterations))."
    }

    private func toolCallPreview(name: String, arguments: String) -> String {
        let isMCP = name.contains("__")
        let icon: String
        if isMCP {
            icon = "🔌"
        } else {
            switch name {
            case "bash":       icon = "⚡"
            case "read_file":  icon = "📄"
            case "write_file": icon = "✏️"
            case "list_dir":   icon = "📁"
            case "web_fetch":  icon = "🌐"
            case "grep":       icon = "🔍"
            default:           icon = "⚙️"
            }
        }

        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "\(icon) \(name)"
        }

        let detail: String
        if isMCP {
            let topKey = args.keys.first ?? ""
            let topVal = args[topKey].map { "\($0)" } ?? ""
            detail = topVal.isEmpty ? "" : "\(topKey)=\(topVal.prefix(60))"
        } else {
            switch name {
            case "bash":
                detail = (args["command"] as? String).map { String($0.prefix(80)) + ($0.count > 80 ? "…" : "") } ?? ""
            case "read_file", "write_file":
                detail = (args["path"] as? String) ?? ""
            case "list_dir":
                detail = (args["path"] as? String) ?? "."
            case "web_fetch":
                detail = (args["url"] as? String) ?? ""
            case "grep":
                detail = "\((args["pattern"] as? String) ?? "") in \((args["path"] as? String) ?? "")"
            default:
                detail = ""
            }
        }

        return detail.isEmpty ? "\(icon) \(name)" : "\(icon) \(name): \(detail)"
    }
}
