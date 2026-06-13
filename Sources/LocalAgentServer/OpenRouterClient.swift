import Foundation

// MARK: - Message types

struct ChatMessage: Codable {
    var role: String
    var content: MessageContent
    var toolCallId: String?
    var toolCalls: [ToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallId = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    init(role: String, text: String) {
        self.role = role
        self.content = .text(text)
    }

    init(role: String, content: MessageContent, toolCallId: String? = nil, toolCalls: [ToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }
}

enum MessageContent: Codable {
    case text(String)
    case parts([ContentPart])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .text(s)
        } else {
            self = .parts(try c.decode([ContentPart].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .parts(let p): try c.encode(p)
        }
    }

    var text: String {
        switch self {
        case .text(let s): return s
        case .parts(let p): return p.compactMap { $0.text }.joined()
        }
    }
}

struct ContentPart: Codable {
    let type: String
    let text: String?
    let imageUrl: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }
}

struct ImageURL: Codable {
    let url: String
}

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: ToolCallFunction
}

struct ToolCallFunction: Codable {
    let name: String
    let arguments: String
}

// MARK: - Tool definitions

struct ToolDefinition: Codable {
    let type: String
    let function: FunctionDefinition
}

struct FunctionDefinition: Codable {
    let name: String
    let description: String
    let parameters: JSONSchema
}

struct JSONSchema: Codable {
    let type: String
    let properties: [String: PropertySchema]
    let required: [String]
}

struct PropertySchema: Codable {
    let type: String
    let description: String
}

// MARK: - OpenRouter response

struct ChatCompletionResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?
}

struct Choice: Decodable {
    let message: AssistantMessage
    let finishReason: String?
    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct AssistantMessage: Decodable {
    let role: String
    let content: String?
    let toolCalls: [ToolCall]?
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

struct Usage: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}

// MARK: - OpenRouter client

struct OpenRouterClient {
    private let apiKey: String
    private let model: String
    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    func complete(
        systemPrompt: String,
        messages: [ChatMessage],
        tools: [ToolDefinition]
    ) async throws -> AssistantMessage {
        var allMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for msg in messages {
            var m: [String: Any] = ["role": msg.role, "content": msg.content.text]
            if let id = msg.toolCallId { m["tool_call_id"] = id }
            if let tcs = msg.toolCalls {
                m["content"] = NSNull()
                m["tool_calls"] = tcs.map { tc -> [String: Any] in
                    ["id": tc.id, "type": tc.type, "function": ["name": tc.function.name, "arguments": tc.function.arguments]]
                }
            }
            allMessages.append(m)
        }

        var body: [String: Any] = [
            "model": model,
            "messages": allMessages,
            "max_tokens": 8192
        ]

        if !tools.isEmpty {
            body["tools"] = tools.map { t -> [String: Any] in
                [
                    "type": t.type,
                    "function": [
                        "name": t.function.name,
                        "description": t.function.description,
                        "parameters": [
                            "type": t.function.parameters.type,
                            "properties": Dictionary(uniqueKeysWithValues: t.function.parameters.properties.map { k, v in
                                (k, ["type": v.type, "description": v.description])
                            }),
                            "required": t.function.parameters.required
                        ]
                    ]
                ]
            }
        }

        let requestData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("LocalAgentServer/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.httpBody = requestData
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw BotError.openRouterError("No HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BotError.openRouterError("HTTP \(http.statusCode): \(body.prefix(500))")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let choice = decoded.choices.first else {
            throw BotError.openRouterError("No choices in response")
        }
        return choice.message
    }
}
