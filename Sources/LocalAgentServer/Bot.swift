import Foundation

actor Bot {
    private let config: Config
    private let telegram: TelegramClient
    private let openRouter: OpenRouterClient
    private let executor: ToolExecutor

    private var conversationHistory: [ChatMessage] = []

    init(config: Config) {
        self.config = config
        self.telegram = TelegramClient(token: config.telegramBotToken)
        self.openRouter = OpenRouterClient(apiKey: config.openRouterApiKey, model: config.openRouterModel)
        self.executor = ToolExecutor(workDir: config.workDir)
    }

    func run() async {
        print("Bot started. Model: \(config.openRouterModel)")
        print("Listening for messages from chat \(config.telegramChatId)")

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

        while iterations < maxIterations {
            iterations += 1

            let response = try await openRouter.complete(
                systemPrompt: config.systemPrompt,
                messages: conversationHistory,
                tools: agentTools
            )

            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                let assistantMsg = ChatMessage(
                    role: "assistant",
                    content: .text(response.content ?? ""),
                    toolCalls: toolCalls
                )
                conversationHistory.append(assistantMsg)

                try? await telegram.sendTyping(chatId: chatId)

                for tc in toolCalls {
                    print("Tool call: \(tc.function.name)(\(tc.function.arguments.prefix(100)))")
                    let result = await executor.execute(name: tc.function.name, arguments: tc.function.arguments)
                    print("Tool result: \(result.prefix(100))")

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

            // Prune history to avoid unbounded growth (keep last 40 messages)
            if conversationHistory.count > 40 {
                conversationHistory = Array(conversationHistory.suffix(40))
            }

            return finalText
        }

        return "Reached maximum tool iterations (\(maxIterations)). Last state saved."
    }
}
