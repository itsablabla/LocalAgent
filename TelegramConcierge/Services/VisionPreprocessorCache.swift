import Foundation
import CryptoKit

/// Caches detailed vision descriptions keyed by content hash.
/// Used by the text-only model preprocessing gate to avoid re-describing
/// the same image or document page on subsequent turns.
actor VisionPreprocessorCache {
    static let shared = VisionPreprocessorCache()

    private let storageKey = "VisionPreprocessorDescriptions"
    private var cache: [String: String] = [:]
    private var loaded = false

    private init() {}

    private func loadIfNeeded() {
        guard !loaded else { return }
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let descriptions = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = descriptions
        }
        loaded = true
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Compute a SHA256 hash of a data URL string for cache keying.
    static func contentHash(_ dataURL: String) -> String {
        let digest = SHA256.hash(data: Data(dataURL.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Get a cached description for a content hash, or nil if not cached.
    func get(hash: String) -> String? {
        loadIfNeeded()
        return cache[hash]
    }

    /// Save a description for a content hash.
    func save(hash: String, description: String) {
        loadIfNeeded()
        cache[hash] = description
        persist()
    }

    /// Save multiple descriptions at once.
    func saveMultiple(_ descriptions: [String: String]) {
        loadIfNeeded()
        for (hash, description) in descriptions {
            cache[hash] = description
        }
        persist()
    }

    /// Clear all cached descriptions.
    func clearAll() {
        cache.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Reload after a Mind restore.
    func reloadFromStorage() {
        cache.removeAll()
        loaded = false
        loadIfNeeded()
    }
}
