import Foundation

struct Config {
    let telegramBotToken: String
    let telegramChatId: Int
    let openRouterApiKey: String
    let openRouterModel: String
    let llmBaseUrl: String
    let assistantName: String
    let userName: String
    let systemPrompt: String
    let workDir: String

    static func fromEnvironment() -> Config {
        let env = ProcessInfo.processInfo.environment

        guard let token = env["TELEGRAM_BOT_TOKEN"], !token.isEmpty else {
            fatalError("TELEGRAM_BOT_TOKEN is required")
        }
        guard let chatIdStr = env["TELEGRAM_CHAT_ID"], let chatId = Int(chatIdStr) else {
            fatalError("TELEGRAM_CHAT_ID is required and must be an integer")
        }
        guard let apiKey = env["OPENROUTER_API_KEY"], !apiKey.isEmpty else {
            fatalError("OPENROUTER_API_KEY is required")
        }

        let model = env["OPENROUTER_MODEL"] ?? "anthropic/claude-sonnet-4-5"
        let llmBaseUrl = env["LLM_BASE_URL"] ?? "https://openrouter.ai/api/v1/chat/completions"
        let assistantName = env["ASSISTANT_NAME"] ?? "Assistant"
        let userName = env["USER_NAME"] ?? "User"
        let workDir = env["WORK_DIR"] ?? FileManager.default.currentDirectoryPath

        let defaultSystemPrompt = """
        You are \(assistantName), an autonomous AI agent. You have access to tools for \
        filesystem operations, bash commands, and web fetching. \
        Today's date is \(formattedDate()). \
        Working directory: \(workDir). \
        Be concise and helpful. Execute tasks autonomously using tools when needed.
        """
        let systemPrompt = env["SYSTEM_PROMPT"] ?? defaultSystemPrompt

        return Config(
            telegramBotToken: token,
            telegramChatId: chatId,
            openRouterApiKey: apiKey,
            openRouterModel: model,
            llmBaseUrl: llmBaseUrl,
            assistantName: assistantName,
            userName: userName,
            systemPrompt: systemPrompt,
            workDir: workDir
        )
    }

    private static func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
