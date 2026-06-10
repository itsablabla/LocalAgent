import Foundation
import AVFoundation
import WhisperKit

@MainActor
final class WhisperKitService: ObservableObject {
    static let shared = WhisperKitService()
    
    // UI state
    @Published var isDownloading = false
    @Published var isLoading = false
    @Published var isCompiling = false
    @Published var downloadProgress: Float = 0
    @Published var statusMessage = "Checking model…"
    @Published var isModelReady = false
    
    // WhisperKit instance
    private var whisperKit: WhisperKit?
    
    // Storage & model identifiers (matching user's other project)
    private let modelStorage = "huggingface/models/argmaxinc/whisperkit-coreml"
    private let repoName = "argmaxinc/whisperkit-coreml"
    private let targetModelName = "openai_whisper-large-v3-v20240930_turbo_632MB"
    
    private var compiledKey: String { "whisperkit_model_compiled_\(targetModelName)" }
    
    // Public helpers
    var hasModelOnDisk: Bool { modelIsDownloaded }
    var isCompiled: Bool { UserDefaults.standard.bool(forKey: compiledKey) }
    
    // Local path to model folder
    private var localModelFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(modelStorage)
                   .appendingPathComponent(targetModelName)
    }
    
    private var modelIsDownloaded: Bool {
        FileManager.default.fileExists(atPath: localModelFolder.path)
    }
    
    private init() {
        checkForAppUpdate()
    }
    
    private func checkForAppUpdate() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let versionKey = "\(currentVersion)_\(currentBuild)"
        
        let lastVersionKey = UserDefaults.standard.string(forKey: "whisperkit_last_app_version") ?? ""
        if lastVersionKey != versionKey && !lastVersionKey.isEmpty {
            UserDefaults.standard.removeObject(forKey: compiledKey)
            print("[WhisperKitService] App updated from \(lastVersionKey) to \(versionKey), reset compilation flag")
        }
        UserDefaults.standard.set(versionKey, forKey: "whisperkit_last_app_version")
    }
    
    // MARK: - Model Status Check
    
    func checkModelStatus() async {
        if !modelIsDownloaded {
            isModelReady = false
            isLoading = false
            isCompiling = false
            statusMessage = "Model not downloaded"
            return
        }
        if !isCompiled {
            isModelReady = false
            isLoading = false
            isCompiling = false
            statusMessage = "Model not compiled"
            return
        }
        await loadModel()
    }
    
    // MARK: - Model Loading
    
    func loadModel() async {
        let firstRunNeedsCompile = !isCompiled
        
        if firstRunNeedsCompile {
            isCompiling = true
            isLoading = false
            statusMessage = "Compiling… this might take a few minutes."
        } else {
            isLoading = true
            isCompiling = false
            statusMessage = "Loading model…"
        }
        
        do {
            var cfg = WhisperKitConfig(model: targetModelName,
                                       modelFolder: localModelFolder.path)
            cfg.download = false
            
            whisperKit = try await WhisperKit(cfg)
            try await whisperKit?.prewarmModels()
            
            if firstRunNeedsCompile {
                UserDefaults.standard.set(true, forKey: compiledKey)
            }
            
            isModelReady = true
            isLoading = false
            isCompiling = false
            statusMessage = "Model ready"
        } catch {
            print("[WhisperKitService] loadModel error:", error)
            isModelReady = false
            isLoading = false
            isCompiling = false
            statusMessage = "Failed to load model"
        }
    }
    
    // MARK: - Model Download
    
    func startDownload() async {
        isDownloading = true
        downloadProgress = 0
        statusMessage = "Downloading transcription model…"
        
        do {
            let folder = try await WhisperKit.download(
                variant: targetModelName,
                from: repoName,
                progressCallback: { progress in
                    DispatchQueue.main.async {
                        self.downloadProgress = Float(progress.fractionCompleted)
                        self.statusMessage = "Downloading… \(Int(progress.fractionCompleted * 100))%"
                    }
                }
            )
            
            // After download, compile once
            isDownloading = false
            isCompiling = true
            statusMessage = "Compiling model…"
            
            var cfg = WhisperKitConfig(model: targetModelName,
                                       modelFolder: folder.path)
            cfg.download = false
            
            whisperKit = try await WhisperKit(cfg)
            try await whisperKit?.prewarmModels()
            
            UserDefaults.standard.set(true, forKey: compiledKey)
            
            isCompiling = false
            isModelReady = true
            statusMessage = "Model ready"
        } catch {
            print("[WhisperKitService] download error:", error)
            isDownloading = false
            isCompiling = false
            isModelReady = false
            statusMessage = "Download failed"
        }
    }
    
    // MARK: - Transcription

    func transcribeAudioFile(url: URL) async -> String? {
        guard let pipe = whisperKit else {
            print("[WhisperKitService] WhisperKit not available")
            return nil
        }

        do {
            let results = try await pipe.transcribe(audioPath: url.path)
            if let firstResult = results.first {
                return firstResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("[WhisperKitService] Transcription error:", error.localizedDescription)
        }

        return nil
    }

    /// A speech segment with absolute timestamps, for SRT generation.
    struct TimedSegment {
        let start: Double
        let end: Double
        let text: String
    }

    /// Transcribe and return timed segments (used by the transcribe_media
    /// tool for SRT output). Strips Whisper special tokens such as
    /// `<|startoftranscript|>` from segment text.
    func transcribeAudioFileSegments(url: URL, language: String? = nil) async -> [TimedSegment]? {
        guard let pipe = whisperKit else {
            print("[WhisperKitService] WhisperKit not available")
            return nil
        }

        do {
            var options = DecodingOptions()
            options.task = .transcribe
            if let language, !language.isEmpty {
                options.language = language
            }
            let results = try await pipe.transcribe(audioPath: url.path, decodeOptions: options)
            var segments: [TimedSegment] = []
            for result in results {
                for segment in result.segments {
                    let cleaned = segment.text
                        .replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleaned.isEmpty else { continue }
                    segments.append(TimedSegment(
                        start: Double(segment.start),
                        end: Double(segment.end),
                        text: cleaned
                    ))
                }
            }
            return segments
        } catch {
            print("[WhisperKitService] Segment transcription error:", error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - Model Deletion
    
    func deleteModelFromDisk() throws {
        whisperKit = nil
        if FileManager.default.fileExists(atPath: localModelFolder.path) {
            try FileManager.default.removeItem(at: localModelFolder)
        }
        UserDefaults.standard.removeObject(forKey: compiledKey)
        isModelReady = false
        isDownloading = false
        isLoading = false
        isCompiling = false
        downloadProgress = 0
        statusMessage = "Model not downloaded"
    }
}

actor OpenAITranscriptionService {
    static let shared = OpenAITranscriptionService()

    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String
        }
        let error: APIError
    }

    func transcribeAudioFile(url: URL, apiKey: String, language: String? = nil) async -> String? {
        guard let data = await performRequest(
            url: url,
            apiKey: apiKey,
            model: "gpt-4o-transcribe",
            responseFormat: nil,
            language: language
        ) else { return nil }

        guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            print("[OpenAITranscriptionService] Failed to decode transcription response")
            return nil
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Transcribe to SRT subtitles. Uses whisper-1 because gpt-4o-transcribe
    /// does not support timestamped response formats.
    func transcribeAudioFileSRT(url: URL, apiKey: String, language: String? = nil) async -> String? {
        guard let data = await performRequest(
            url: url,
            apiKey: apiKey,
            model: "whisper-1",
            responseFormat: "srt",
            language: language
        ) else { return nil }

        let srt = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let srt, !srt.isEmpty else {
            print("[OpenAITranscriptionService] Empty SRT response")
            return nil
        }
        return srt
    }

    /// Shared multipart upload to the OpenAI transcriptions endpoint.
    /// Returns the raw response body on HTTP 200, nil otherwise.
    private func performRequest(
        url: URL,
        apiKey: String,
        model: String,
        responseFormat: String?,
        language: String?
    ) async -> Data? {
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedApiKey.isEmpty else {
            print("[OpenAITranscriptionService] Missing API key")
            return nil
        }

        guard let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            print("[OpenAITranscriptionService] Invalid endpoint URL")
            return nil
        }

        do {
            let fileData = try Data(contentsOf: url)
            let boundary = "Boundary-\(UUID().uuidString)"

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 300
            request.setValue("Bearer \(trimmedApiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            func appendField(name: String, value: String) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }

            appendField(name: "model", value: model)
            if let responseFormat {
                appendField(name: "response_format", value: responseFormat)
            }
            if let language, !language.isEmpty {
                appendField(name: "language", value: language)
            }

            let filename = url.lastPathComponent.isEmpty ? "voice.ogg" : url.lastPathComponent
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType(for: url))\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)

            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[OpenAITranscriptionService] Invalid HTTP response")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                    print("[OpenAITranscriptionService] API error (HTTP \(httpResponse.statusCode)): \(apiError.error.message)")
                } else if let bodyText = String(data: data, encoding: .utf8), !bodyText.isEmpty {
                    print("[OpenAITranscriptionService] API error (HTTP \(httpResponse.statusCode)): \(bodyText.prefix(200))")
                } else {
                    print("[OpenAITranscriptionService] API error (HTTP \(httpResponse.statusCode))")
                }
                return nil
            }

            return data
        } catch {
            print("[OpenAITranscriptionService] Transcription error: \(error.localizedDescription)")
            return nil
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "ogg", "oga":
            return "audio/ogg"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        default:
            return "application/octet-stream"
        }
    }
}
