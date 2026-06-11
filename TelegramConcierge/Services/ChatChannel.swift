import Foundation

/// Which messaging transport a conversation message travelled over.
enum ChannelKind: String, Codable, CaseIterable {
    case telegram
    case whatsapp

    var displayName: String {
        switch self {
        case .telegram: return "Telegram"
        case .whatsapp: return "WhatsApp"
        }
    }
}

/// A fully-qualified destination for outbound messages: the transport plus the
/// transport-native chat identifier (Telegram numeric chat id as a string,
/// WhatsApp JID like "39333...@s.whatsapp.net").
struct ChannelAddress: Codable, Equatable, Hashable {
    let kind: ChannelKind
    let chatId: String
}

/// Outbound surface every messaging transport must provide. Inbound delivery is
/// transport-specific (Telegram long-polls, WhatsApp pushes from a sidecar), so
/// only the send side is abstracted; ConversationManager routes each turn's
/// output to the channel its triggering message arrived on.
protocol ChatChannel: Sendable {
    var kind: ChannelKind { get }
    func sendText(chatId: String, text: String) async throws
    func sendPhoto(chatId: String, imageData: Data, caption: String?, mimeType: String) async throws
    func sendDocument(chatId: String, documentData: Data, filename: String, caption: String?, mimeType: String) async throws
}

// MARK: - Telegram conformance

extension TelegramBotService: ChatChannel {
    nonisolated var kind: ChannelKind { .telegram }

    func sendText(chatId: String, text: String) async throws {
        guard let numericId = Int(chatId) else {
            throw TelegramError.apiError("Invalid Telegram chat id: \(chatId)")
        }
        try await sendMessage(chatId: numericId, text: text)
    }

    func sendPhoto(chatId: String, imageData: Data, caption: String?, mimeType: String) async throws {
        guard let numericId = Int(chatId) else {
            throw TelegramError.apiError("Invalid Telegram chat id: \(chatId)")
        }
        try await sendPhoto(chatId: numericId, imageData: imageData, caption: caption, mimeType: mimeType)
    }

    func sendDocument(chatId: String, documentData: Data, filename: String, caption: String?, mimeType: String) async throws {
        guard let numericId = Int(chatId) else {
            throw TelegramError.apiError("Invalid Telegram chat id: \(chatId)")
        }
        try await sendDocument(chatId: numericId, documentData: documentData, filename: filename, caption: caption, mimeType: mimeType)
    }
}
