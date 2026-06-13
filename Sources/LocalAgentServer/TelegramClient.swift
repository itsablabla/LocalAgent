import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Telegram API Types

struct TelegramResponse<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
    let description: String?
}

struct TelegramUpdate: Decodable {
    let updateId: Int
    let message: TelegramMessage?
    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
    }
}

struct TelegramMessage: Decodable {
    let messageId: Int
    let from: TelegramUser?
    let chat: TelegramChat
    let text: String?
    let voice: TelegramVoice?
    let photo: [TelegramPhotoSize]?
    let document: TelegramDocument?
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case from, chat, text, voice, photo, document
    }
}

struct TelegramUser: Decodable {
    let id: Int
    let firstName: String
    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
    }
}

struct TelegramChat: Decodable {
    let id: Int
}

struct TelegramVoice: Decodable {
    let fileId: String
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
    }
}

struct TelegramPhotoSize: Decodable {
    let fileId: String
    let width: Int
    let height: Int
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case width, height
    }
}

struct TelegramDocument: Decodable {
    let fileId: String
    let fileName: String?
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case fileName = "file_name"
    }
}

struct TelegramFile: Decodable {
    let fileId: String
    let filePath: String?
    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case filePath = "file_path"
    }
}

// MARK: - Telegram Client

actor TelegramClient {
    private let baseURL = "https://api.telegram.org/bot"
    private let token: String
    private var lastUpdateId: Int = 0

    init(token: String) {
        self.token = token
    }

    func getUpdates() async throws -> [TelegramUpdate] {
        var components = URLComponents(string: "\(baseURL)\(token)/getUpdates")!
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(lastUpdateId + 1)),
            URLQueryItem(name: "timeout", value: "25"),
            URLQueryItem(name: "allowed_updates", value: "[\"message\"]")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 35

        let (data, response) = try await URLSession.shared.fetchData(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BotError.telegramError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let decoded = try JSONDecoder().decode(TelegramResponse<[TelegramUpdate]>.self, from: data)
        guard decoded.ok, let updates = decoded.result else {
            throw BotError.telegramError(decoded.description ?? "Unknown")
        }
        if let last = updates.last { lastUpdateId = last.updateId }
        return updates
    }

    func sendMessage(chatId: Int, text: String) async throws {
        let url = URL(string: "\(baseURL)\(token)/sendMessage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let safe = sanitize(text)
        let body: [String: Any] = ["chat_id": chatId, "text": safe]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.fetchData(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BotError.telegramError("sendMessage HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(body.prefix(200))")
        }
    }

    func sendTyping(chatId: Int) async throws {
        let url = URL(string: "\(baseURL)\(token)/sendChatAction")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = ["chat_id": chatId, "action": "typing"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.fetchData(for: request)
    }

    private func sanitize(_ text: String) -> String {
        var t = text
        // Strip Markdown that Telegram doesn't handle well
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "__", with: "")
        // Truncate to Telegram's 4096 UTF-16 limit
        if t.utf16.count > 4096 {
            var used = 0
            var end = t.startIndex
            for idx in t.indices {
                let len = t[idx].utf16.count
                if used + len > 4096 { break }
                used += len
                end = t.index(after: idx)
            }
            t = String(t[..<end]) + "…"
        }
        return t
    }
}

enum BotError: Error, LocalizedError {
    case telegramError(String)
    case openRouterError(String)
    case toolError(String)

    var errorDescription: String? {
        switch self {
        case .telegramError(let m): return "Telegram: \(m)"
        case .openRouterError(let m): return "OpenRouter: \(m)"
        case .toolError(let m): return "Tool: \(m)"
        }
    }
}
