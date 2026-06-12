import SwiftUI
import AppKit
import CoreImage

/// Reports the bottom edge (maxY) of the onboarding scroll content in the
/// scroll view's coordinate space, so the view can tell when content
/// overflows below the fold.
private struct OnboardingContentFrameKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct OnboardingView: View {
    @EnvironmentObject var conversationManager: ConversationManager
    @Binding var isComplete: Bool

    @State private var step = 0
    @State private var isDescriptionModelExpanded: Bool = false
    @State private var scrollContentBottom: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0
    private let totalRequiredSteps = 4 // 0=welcome, 1=LLM, 2=persona, 3=channels
    private let totalOptionalSteps = 4 // 4=voice, 5=websearch, 6=email, 7=imagegen

    // LLM Provider
    @State private var llmProvider: String = "lmstudio"
    @State private var apiChoice: String = "opencode" // "opencode" | "openrouter" | "custom"
    @State private var openRouterApiKey: String = ""
    @State private var openRouterModel: String = ""
    @State private var lmStudioBaseURL: String = ""
    @State private var lmStudioModel: String = ""
    @State private var lmStudioDescriptionModel: String = ""
    @State private var lmStudioDescriptionBaseURL: String = ""
    @State private var openAICompatibleBaseURL: String = ""
    @State private var openAICompatibleModel: String = ""
    @State private var openAICompatibleApiKey: String = ""
    @State private var openAICompatibleReasoningEffort: String = ""

    // OpenCode Go preset (the recommended cloud setup)
    private static let openCodeGoBaseURL = "https://opencode.ai/zen/go/v1"
    private static let openCodeGoModel = "kimi-k2.6"

    // Persona
    @State private var assistantName: String = ""
    @State private var userName: String = ""
    @State private var userContext: String = ""

    // Channels
    @State private var telegramSelected: Bool = true
    @State private var whatsappSelected: Bool = false
    @State private var telegramToken: String = ""
    @State private var chatId: String = ""
    @State private var isTesting: Bool = false
    @State private var botInfo: String?
    @State private var testError: String?
    @State private var whatsappOwnerPhone: String = ""
    @ObservedObject private var whatsAppService = WhatsAppChannelService.shared
    private let telegramService = TelegramBotService()

    // Voice
    @State private var voiceTranscriptionProvider: VoiceTranscriptionProvider = .openAI
    @State private var openAITranscriptionApiKey: String = ""
    @ObservedObject private var whisper = WhisperKitService.shared

    // Web Search
    @State private var serperApiKey: String = ""
    @State private var jinaApiKey: String = ""

    // Google Workspace is configured outside the app via the `gws` CLI —
    // no in-app state to carry for this step.

    // Image Gen
    @State private var imageGenerationProvider: String = ImageGenerationProvider.gemini.rawValue
    @State private var geminiApiKey: String = ""
    @State private var openAIImageApiKey: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                let progress = Double(step) / Double(totalRequiredSteps + totalOptionalSteps)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .frame(height: 4)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch step {
                        case 0: welcomeStep
                        case 1: llmProviderStep
                        case 2: personaStep
                        case 3: channelsStep
                        case 4: optionalGateStep
                        case 5: voiceStep
                        case 6: webSearchStep
                        case 7: emailStep
                        case 8: imageGenStep
                        default: doneStep
                        }
                    }
                    .padding(30)
                    .id("onboardingTop")
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: OnboardingContentFrameKey.self,
                                value: proxy.frame(in: .named("onboardingScroll")).maxY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "onboardingScroll")
                .scrollIndicators(.visible)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { scrollViewportHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, newValue in
                                scrollViewportHeight = newValue
                            }
                    }
                )
                .onPreferenceChange(OnboardingContentFrameKey.self) { maxY in
                    scrollContentBottom = maxY
                }
                .overlay(alignment: .bottom) {
                    if hasMoreContentBelow {
                        scrollDownHint
                    }
                }
                .onChange(of: step) { _, _ in
                    scrollProxy.scrollTo("onboardingTop", anchor: .top)
                }
            }

            Divider()

            // Navigation buttons
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                }

                Spacer()

                if step == 4 {
                    // Optional gate — two buttons
                    Button("Skip, start agent") { finishOnboarding() }
                        .buttonStyle(.bordered)
                    Button("Continue setup") { step = 5 }
                        .buttonStyle(.borderedProminent)
                } else if step >= 5 && step <= 8 {
                    Button("Skip") { step += 1 }
                        .buttonStyle(.bordered)
                    Button("Next") {
                        saveCurrentStep()
                        step += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else if step == 9 {
                    Button("Start Agent") { finishOnboarding() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else if step == 0 {
                    Button("Get Started") { step = 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Next") {
                        saveCurrentStep()
                        step += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isCurrentStepValid)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 15)
        }
        .frame(width: 580, height: 700)
        .onAppear { loadExistingSettings() }
    }

    // MARK: - Scroll overflow hint

    /// True when the step's content extends below the visible scroll area —
    /// macOS hides scrollbars until the user scrolls, so without this a
    /// distracted user has no cue that more fields exist below the fold.
    private var hasMoreContentBelow: Bool {
        scrollContentBottom > scrollViewportHeight + 12
    }

    private var scrollDownHint: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor).opacity(0),
                Color(nsColor: .windowBackgroundColor)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Label("Scroll for more", systemImage: "chevron.down")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("Welcome to Telegram Concierge")
                .font(.title.bold())

            Text("Your personal AI assistant that lives in your messaging app — Telegram, WhatsApp, or both. Let's set it up in a few steps.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var llmProviderStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("LLM Provider", systemImage: "brain.head.profile")
                .font(.title2.bold())

            Text("Choose which AI model powers your assistant. Without this, nothing works.")
                .font(.callout)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                setupModeCard(
                    title: "Local",
                    icon: "desktopcomputer",
                    subtitle: "Models run on your own hardware. Private and free — needs a capable machine.",
                    isSelected: llmProvider == "lmstudio"
                ) {
                    llmProvider = "lmstudio"
                }
                setupModeCard(
                    title: "Cloud API",
                    icon: "cloud.fill",
                    subtitle: "A hosted frontier model via API. Best quality, no hardware needed.",
                    isSelected: llmProvider != "lmstudio"
                ) {
                    selectAPIMode()
                }
            }

            if llmProvider == "lmstudio" {
                localProviderConfig
            } else {
                apiProviderConfig
            }
        }
    }

    private func setupModeCard(title: String, icon: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func selectAPIMode() {
        switch apiChoice {
        case "openrouter":
            llmProvider = "openrouter"
        default:
            llmProvider = "openai_compatible"
            if apiChoice == "opencode" { applyOpenCodePreset() }
        }
    }

    private func applyOpenCodePreset() {
        openAICompatibleBaseURL = Self.openCodeGoBaseURL
        openAICompatibleModel = Self.openCodeGoModel
        openAICompatibleReasoningEffort = "high"
    }

    @ViewBuilder
    private var localProviderConfig: some View {
        Group {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Server")
                            .font(.headline)

                        Picker("Server", selection: Binding(
                            get: { onboardingLocalPreset(from: lmStudioBaseURL) },
                            set: { preset in
                                if let url = onboardingLocalPresetURL(preset) { lmStudioBaseURL = url }
                            }
                        )) {
                            Text("LM Studio").tag("lmstudio")
                            Text("Ollama").tag("ollama")
                            Text("vLLM").tag("vllm")
                            Text("Custom").tag("custom")
                        }
                        .pickerStyle(.segmented)

                        TextField("Base URL", text: $lmStudioBaseURL)
                            .textFieldStyle(.roundedBorder)
                        Text("Any OpenAI-compatible server works. Select a preset or enter a custom URL.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        TextField("Model Name", text: $lmStudioModel)
                            .textFieldStyle(.roundedBorder)
                        Text("Recommended: Gemma 4 26B or Gemma 4 31B — excellent reasoning and tool use. Use a multimodal model so the assistant can see images and documents.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Provider-specific caching note
                        Group {
                            let preset = onboardingLocalPreset(from: lmStudioBaseURL)
                            if preset == "vllm" {
                                Text("⚠️ vLLM: start with --enable-prefix-caching for prompt cache reuse.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else if preset == "custom" {
                                Text("Prompt caching depends on your server. llama.cpp-based servers cache automatically. vLLM needs --enable-prefix-caching. MLX only caches for full-attention models.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        DisclosureGroup("Description Model", isExpanded: $isDescriptionModelExpanded) {
                            TextField("Description Model", text: $lmStudioDescriptionModel)
                                .textFieldStyle(.roundedBorder)
                            Text("A separate multimodal model for generating file descriptions at pruning time. Use a faster model here to speed up the process.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextField("Description Base URL (optional)", text: $lmStudioDescriptionBaseURL)
                                .textFieldStyle(.roundedBorder)
                            Text("If the description model runs on a different port.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Text("Web search and deep research always run on cloud models via OpenRouter — you'll add that key in a later step. Your conversations stay local either way.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

    @ViewBuilder
    private var apiProviderConfig: some View {
        Group {
            Picker("Service", selection: Binding(
                get: { apiChoice },
                set: { choice in
                    apiChoice = choice
                    selectAPIMode()
                }
            )) {
                Text("OpenCode (Recommended)").tag("opencode")
                Text("OpenRouter").tag("openrouter")
                Text("Custom").tag("custom")
            }
            .pickerStyle(.segmented)

            if apiChoice == "opencode" {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("OpenCode Go — best value", systemImage: "star.fill")
                            .font(.headline)
                            .foregroundColor(.accentColor)

                        Text("The cheapest way to run LocalAgent with frontier quality: OpenCode's Go subscription ($5 the first month, then $10/month) gives you Kimi K2.6 with high reasoning through an OpenAI-compatible endpoint. Everything below is pre-configured — just add your API key.")
                            .font(.callout)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Endpoint: \(Self.openCodeGoBaseURL)")
                            Text("Model: \(Self.openCodeGoModel)")
                            Text("Reasoning: High")
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                        Link("Subscribe and get your API key at opencode.ai/go", destination: URL(string: "https://opencode.ai/go")!)
                            .font(.callout)

                        SecureField("OpenCode API Key (sk-…)", text: $openAICompatibleApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            } else if apiChoice == "openrouter" {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        SecureField("OpenRouter API Key", text: $openRouterApiKey)
                            .textFieldStyle(.roundedBorder)
                        Text("Get your key from openrouter.ai/keys")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Model (optional)", text: $openRouterModel)
                            .textFieldStyle(.roundedBorder)
                        Text("Leave empty for Gemini Flash. Or use ~google/gemini-flash-latest, anthropic/claude-sonnet-4, etc.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Base URL", text: $openAICompatibleBaseURL)
                            .textFieldStyle(.roundedBorder)
                        Text("Any OpenAI-compatible endpoint implementing /v1/chat/completions (e.g. https://api.example.com/v1).")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Model Name", text: $openAICompatibleModel)
                            .textFieldStyle(.roundedBorder)

                        SecureField("API Key", text: $openAICompatibleApiKey)
                            .textFieldStyle(.roundedBorder)
                        Text("Sent as a Bearer token to your endpoint. Use a multimodal model so the assistant can see images and documents.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Reasoning Effort", selection: $openAICompatibleReasoningEffort) {
                            Text("Not Specified").tag("")
                            Text("Minimal").tag("minimal")
                            Text("Low").tag("low")
                            Text("Medium").tag("medium")
                            Text("High").tag("high")
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            if apiChoice != "openrouter" {
                Text("Web search and deep research run on OpenRouter models — you'll add an OpenRouter key in a later step.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var personaStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Persona", systemImage: "person.text.rectangle")
                .font(.title2.bold())

            Text("Tell your assistant who it is and who you are.")
                .font(.callout)
                .foregroundColor(.secondary)

            TextField("Assistant Name", text: $assistantName)
                .textFieldStyle(.roundedBorder)
            Text("What you want to call your assistant.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Your Name", text: $userName)
                .textFieldStyle(.roundedBorder)

            Text("About You")
                .font(.headline)
            TextEditor(text: $userContext)
                .font(.body)
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            Text("Describe yourself, your interests, and how you'd like the assistant to behave. This helps personalize responses. You can refine this later in Settings > Identity.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var channelsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Messaging Channel", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.title2.bold())

            Text("You'll talk to your assistant from your phone. Pick at least one channel — you can enable both.")
                .font(.callout)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                setupModeCard(
                    title: "Telegram",
                    icon: "paperplane.fill",
                    subtitle: "A free bot account. Quickest to set up — no extra hardware needed.",
                    isSelected: telegramSelected
                ) {
                    telegramSelected.toggle()
                }
                setupModeCard(
                    title: "WhatsApp",
                    icon: "message.fill",
                    subtitle: "The agent gets its own WhatsApp number. Needs a spare phone with a second SIM.",
                    isSelected: whatsappSelected
                ) {
                    whatsappSelected.toggle()
                }
            }

            if !telegramSelected && !whatsappSelected {
                Text("Select at least one channel to continue.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if telegramSelected {
                telegramSetupSection
            }

            if whatsappSelected {
                whatsappSetupSection
            }
        }
    }

    @ViewBuilder
    private var telegramSetupSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Telegram", systemImage: "paperplane.fill")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Create your bot:")
                        .font(.subheadline.bold())
                    Text("1. Open Telegram and search for @BotFather")
                    Text("2. Send /newbot and follow the prompts")
                    Text("3. Choose a name (e.g., \"My Concierge\") and a username (e.g., \"my_concierge_bot\")")
                    Text("4. BotFather will give you a token — paste it below")
                }
                .font(.callout)

                SecureField("Bot Token", text: $telegramToken)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Get your Chat ID:")
                        .font(.subheadline.bold())
                    Text("1. Search for @userinfobot on Telegram")
                    Text("2. Send /start — it replies with your user ID")
                    Text("3. Paste that number below")
                }
                .font(.callout)

                TextField("Your Chat ID", text: $chatId)
                    .textFieldStyle(.roundedBorder)

                if !telegramToken.isEmpty {
                    HStack {
                        Button("Test Connection") { testConnection() }
                            .buttonStyle(.bordered)
                            .disabled(isTesting)

                        if isTesting {
                            ProgressView().scaleEffect(0.7)
                        }
                        if let info = botInfo {
                            Label(info, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        if let error = testError {
                            Label(error, systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var whatsappSetupSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("WhatsApp", systemImage: "message.fill")
                    .font(.headline)

                Text("The agent needs its own WhatsApp account, separate from yours. That means a second phone number — a cheap prepaid SIM or eSIM works. You link it once below; after that, the spare phone can stay off in a drawer.")
                    .font(.callout)

                VStack(alignment: .leading, spacing: 6) {
                    Text("1. On a spare phone, install WhatsApp and register it with the agent's new number (it only needs to receive one SMS).")
                    Text("2. Below, enter your own WhatsApp number — NOT the agent's. This locks the agent so it only ever talks to you.")
                    Text("3. Press Start Pairing, then on the spare phone: WhatsApp → Settings → Linked Devices → Link a Device → scan the QR code.")
                    Text("4. Once connected, turn the spare phone off and put it away.")
                }
                .font(.callout)

                TextField("Your personal WhatsApp number (e.g. +39 333 1234567)", text: $whatsappOwnerPhone)
                    .textFieldStyle(.roundedBorder)

                Text("This is YOUR number — the phone you'll message from. The agent's own number is never typed anywhere; scanning the QR code is what links it.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if whatsAppService.state == .disabled {
                    Button("Start Pairing") { startWhatsAppPairing() }
                        .buttonStyle(.borderedProminent)
                        .disabled(whatsappOwnerPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(whatsAppService.state.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(whatsAppService.state.description)
                            .font(.caption)
                            .foregroundColor(whatsAppService.state.isConnected ? .green : .secondary)
                    }

                    if let qr = whatsAppService.qrString, let image = Self.qrImage(from: qr) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                        Text("Scan with the agent's phone: WhatsApp → Settings → Linked Devices → Link a Device.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if whatsAppService.state.isConnected {
                        Label("Connected — you can turn the agent's phone off now.", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func startWhatsAppPairing() {
        let phone = whatsappOwnerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty else { return }
        try? KeychainHelper.save(key: KeychainHelper.whatsappOwnerPhoneKey, value: phone)
        WhatsAppChannelService.shared.isEnabled = true
        Task { await conversationManager.updateWhatsAppChannelRegistration() }
    }

    private static func qrImage(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private var optionalGateStep: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)

            Text("Core Setup Complete!")
                .font(.title2.bold())

            Text("Your assistant can now connect to your messaging app and respond to messages. However, without the following services it won't be able to do much beyond basic conversation.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 6) {
                Label("Voice Transcription — understand your voice messages", systemImage: "waveform")
                Label("Web Search — search the internet and read web pages", systemImage: "magnifyingglass")
                Label("Google Workspace — Gmail, Calendar, Contacts, Drive via the gws CLI", systemImage: "envelope")
                Label("Image Generation — create and edit images", systemImage: "photo.badge.plus")
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)

            Text("We strongly recommend continuing to set up at least a few of these.")
                .font(.callout.bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var voiceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Voice Transcription", systemImage: "waveform")
                .font(.title2.bold())

            Text("Transcribe the voice messages you send in chat.")
                .font(.callout)
                .foregroundColor(.secondary)

            Picker("Method", selection: $voiceTranscriptionProvider) {
                ForEach(VoiceTranscriptionProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            if voiceTranscriptionProvider == .openAI {
                SecureField("OpenAI API Key", text: $openAITranscriptionApiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Used for gpt-4o-transcribe. Fast and accurate.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Link("Get an API key at platform.openai.com/api-keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Download the Whisper model once (~630 MB) and your voice messages are transcribed on-device — private and free, no API key needed.")
                            .font(.callout)

                        HStack(spacing: 8) {
                            if whisper.isModelReady {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Model ready")
                                    .font(.callout)
                                    .foregroundColor(.green)
                            } else if whisper.isDownloading || whisper.isCompiling || whisper.isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(whisper.statusMessage)
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            } else if !whisper.hasModelOnDisk {
                                Button("Download Whisper Model") {
                                    Task { await whisper.startDownload() }
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button("Prepare Model") {
                                    Task { await whisper.loadModel() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        if whisper.isDownloading {
                            ProgressView(value: Double(whisper.downloadProgress))
                                .progressViewStyle(.linear)
                        }

                        if !whisper.isModelReady {
                            Text("You can continue the setup while it downloads — everything finishes in the background, and from then on the model prepares itself automatically at every launch.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    // If the model is already on disk (e.g. re-running onboarding
                    // after an update), prepare it without any button press.
                    if whisper.hasModelOnDisk {
                        Task { await whisper.checkModelStatus() }
                    }
                }
            }
        }
    }

    private var webSearchStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Web Search", systemImage: "magnifyingglass")
                .font(.title2.bold())

            Text("Lets your assistant search Google, read web pages, and run deep multi-source research. It takes three small services working together — each has a key, all set up in a minute. Only search queries are ever sent to them, never your conversation.")
                .font(.callout)
                .foregroundColor(.secondary)

            if llmProvider != "openrouter" {
                webSearchKeyBox(
                    title: "Search Brain — OpenRouter",
                    icon: "brain.head.profile",
                    why: "Runs the fast AI models that drive the search: they decide what to look up, read the results, and write the answer. Required even though your main model doesn't use OpenRouter.",
                    linkLabel: "Get a key at openrouter.ai/keys",
                    url: "https://openrouter.ai/keys"
                ) {
                    SecureField("OpenRouter API Key", text: $openRouterApiKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            webSearchKeyBox(
                title: "Google Search — Serper",
                icon: "magnifyingglass",
                why: "Performs the actual Google searches. Free tier: 2,500 searches.",
                linkLabel: "Get a free key at serper.dev",
                url: "https://serper.dev"
            ) {
                SecureField("Serper API Key", text: $serperApiKey)
                    .textFieldStyle(.roundedBorder)
            }

            webSearchKeyBox(
                title: "Page Reader — Jina",
                icon: "doc.plaintext",
                why: "Turns the web pages found into clean text the assistant can read. Free tier available.",
                linkLabel: "Get a free key at jina.ai",
                url: "https://jina.ai"
            ) {
                SecureField("Jina API Key", text: $jinaApiKey)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func webSearchKeyBox<Field: View>(
        title: String,
        icon: String,
        why: String,
        linkLabel: String,
        url: String,
        @ViewBuilder field: () -> Field
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Text(why)
                    .font(.callout)
                    .foregroundColor(.secondary)
                Link(linkLabel, destination: URL(string: url)!)
                    .font(.callout)
                field()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emailStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Google Workspace (gws CLI)", systemImage: "envelope.fill")
                    .font(.title2.bold())

                Text("Gives your assistant Gmail, Calendar, Contacts, and Drive — it reads your inbox and agenda ambiently and can act on them. Everything happens in the terminal; the browser only opens to sign in.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                GroupBox(label: Text("1. Install the two CLIs").font(.headline)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("brew install gws")
                            .font(.system(.callout, design: .monospaced))
                            .padding(6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        Text("brew install --cask google-cloud-sdk")
                            .font(.system(.callout, design: .monospaced))
                            .padding(6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        Text("gws is the Workspace CLI; Google's gcloud is needed once, for the automated setup in step 2.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Link("gws on GitHub", destination: URL(string: "https://github.com/workspace-cli/gws")!)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("2. Sign in and run the automated setup").font(.headline)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("gcloud auth login")
                            .font(.system(.callout, design: .monospaced))
                            .padding(6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        Text("Prints a URL — open it, sign in with your Google account. Then:")
                            .font(.callout)
                        Text("gws auth setup --login")
                            .font(.system(.callout, design: .monospaced))
                            .padding(6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        Text("This single command creates the Google Cloud project, enables the Workspace APIs, creates the OAuth client, and opens the final sign-in where you grant access. No Cloud Console clicking needed.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Text("3. Verify").font(.headline)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quick sanity checks — both should print JSON:")
                            .font(.callout)
                        Text("gws gmail +triage --query 'is:unread' --format json")
                            .font(.system(.callout, design: .monospaced))
                        Text("gws calendar +agenda --today --format json")
                            .font(.system(.callout, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Your assistant auto-discovers gws on next launch. If it's not installed or not authenticated, the inbox/calendar blocks are silently skipped and everything else still works — you can set this up any time later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    private var imageGenStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Image Generation", systemImage: "photo.badge.plus")
                .font(.title2.bold())

            Text("Let your assistant generate and edit images. Pick a provider — you can switch later in Settings.")
                .font(.callout)
                .foregroundColor(.secondary)

            Picker("Provider", selection: $imageGenerationProvider) {
                ForEach(ImageGenerationProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if ImageGenerationProvider.fromStoredValue(imageGenerationProvider) == .gemini {
                SecureField("Gemini API Key", text: $geminiApiKey)
                    .textFieldStyle(.roundedBorder)

                Link("Get your key from Google AI Studio", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.caption)
            } else {
                SecureField("OpenAI API Key", text: $openAIImageApiKey)
                    .textFieldStyle(.roundedBorder)

                Link("Get your key at platform.openai.com/api-keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)

                Text("Uses OpenAI's image model (\(KeychainHelper.defaultOpenAIImageModel) by default). Quality and format options are in Settings > Services.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .center, spacing: 20) {
            Spacer()
            Image(systemName: "party.popper.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("You're all set!")
                .font(.title.bold())

            Text("Your assistant is configured and ready. You can always adjust settings later via the Settings panel (Cmd+,) or restart this onboarding from Settings > Data.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Validation

    private var isCurrentStepValid: Bool {
        switch step {
        case 1:
            switch llmProvider {
            case "lmstudio":
                return true // defaults cover the local setup
            case "openrouter":
                return !openRouterApiKey.isEmpty
            default: // openai_compatible
                if apiChoice == "opencode" {
                    return !openAICompatibleApiKey.isEmpty
                }
                return !openAICompatibleApiKey.isEmpty
                    && !openAICompatibleBaseURL.isEmpty
                    && !openAICompatibleModel.isEmpty
            }
        case 2: return true // persona is optional
        case 3:
            guard telegramSelected || whatsappSelected else { return false }
            let telegramOK = !telegramToken.isEmpty && !chatId.isEmpty
            let whatsappOK = !whatsappOwnerPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return (!telegramSelected || telegramOK) && (!whatsappSelected || whatsappOK)
        default: return true
        }
    }

    // MARK: - Save Logic

    private func saveCurrentStep() {
        switch step {
        case 1: saveLLMProvider()
        case 2: savePersona()
        case 3: saveChannels()
        case 5: saveVoice()
        case 6: saveWebSearch()
        case 7: saveEmail()
        case 8: saveImageGen()
        default: break
        }
    }

    private func saveLLMProvider() {
        try? KeychainHelper.save(key: KeychainHelper.llmProviderKey, value: llmProvider)
        // Only persist the OpenRouter key here when OpenRouter is the chosen
        // provider — otherwise it's collected later in the Web Search step.
        if llmProvider == "openrouter" || !openRouterApiKey.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.openRouterApiKeyKey, value: openRouterApiKey)
        }
        if !openRouterModel.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.openRouterModelKey, value: openRouterModel)
        }
        if llmProvider == "openai_compatible" {
            if apiChoice == "opencode" { applyOpenCodePreset() }
            let trimmedBase = openAICompatibleBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBase.isEmpty {
                try? KeychainHelper.save(key: KeychainHelper.openAICompatibleBaseURLKey, value: trimmedBase)
            }
            let trimmedModel = openAICompatibleModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedModel.isEmpty {
                try? KeychainHelper.save(key: KeychainHelper.openAICompatibleModelKey, value: trimmedModel)
            }
            let trimmedKey = openAICompatibleApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                try? KeychainHelper.save(key: KeychainHelper.openAICompatibleApiKeyKey, value: trimmedKey)
            }
            if !openAICompatibleReasoningEffort.isEmpty {
                try? KeychainHelper.save(key: KeychainHelper.openAICompatibleReasoningEffortKey, value: openAICompatibleReasoningEffort)
            }
        }
        if llmProvider == "lmstudio" {
            let trimmedBase = lmStudioBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBase.isEmpty {
                try? KeychainHelper.save(key: KeychainHelper.lmStudioBaseURLKey, value: trimmedBase)
            }
            let trimmedModel = lmStudioModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedModel.isEmpty {
                try? KeychainHelper.save(key: KeychainHelper.lmStudioModelKey, value: trimmedModel)
            }
            let trimmedDescModel = lmStudioDescriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDescModel.isEmpty {
                try? KeychainHelper.save(key: KeychainHelper.lmStudioDescriptionModelKey, value: trimmedDescModel)
            }
            let trimmedDescURL = lmStudioDescriptionBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDescURL.isEmpty {
                try? KeychainHelper.save(key: KeychainHelper.lmStudioDescriptionBaseURLKey, value: trimmedDescURL)
            }
        }
    }

    private func savePersona() {
        try? KeychainHelper.save(key: KeychainHelper.assistantNameKey, value: assistantName)
        try? KeychainHelper.save(key: KeychainHelper.userNameKey, value: userName)
        if !userContext.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.structuredUserContextKey, value: userContext)
        }
    }

    private func saveChannels() {
        if telegramSelected && !telegramToken.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.telegramBotTokenKey, value: telegramToken)
            try? KeychainHelper.save(key: KeychainHelper.telegramChatIdKey, value: chatId)
        }
        let phone = whatsappOwnerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        if whatsappSelected && !phone.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.whatsappOwnerPhoneKey, value: phone)
            WhatsAppChannelService.shared.isEnabled = true
        } else if !whatsappSelected && WhatsAppChannelService.shared.isEnabled {
            // Deselected during a re-run of onboarding: turn the channel off.
            WhatsAppChannelService.shared.isEnabled = false
        }
        Task { await conversationManager.updateWhatsAppChannelRegistration() }
    }

    private func saveVoice() {
        try? KeychainHelper.save(key: KeychainHelper.voiceTranscriptionProviderKey, value: voiceTranscriptionProvider.rawValue)
        if voiceTranscriptionProvider == .openAI && !openAITranscriptionApiKey.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.openAITranscriptionApiKeyKey, value: openAITranscriptionApiKey)
        }
    }

    private func saveWebSearch() {
        if !openRouterApiKey.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.openRouterApiKeyKey, value: openRouterApiKey)
        }
        if !serperApiKey.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.serperApiKeyKey, value: serperApiKey)
        }
        if !jinaApiKey.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.jinaApiKeyKey, value: jinaApiKey)
        }
    }

    private func saveEmail() {
        // Google Workspace is configured entirely outside the app — via the
        // `gws` CLI — so this step has nothing to persist. Kept as a no-op so
        // the step index mapping doesn't shift.
    }

    private func saveImageGen() {
        let provider = ImageGenerationProvider.fromStoredValue(imageGenerationProvider)
        try? KeychainHelper.save(key: KeychainHelper.imageGenerationProviderKey, value: provider.rawValue)
        if !geminiApiKey.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.geminiApiKeyKey, value: geminiApiKey)
        }
        if !openAIImageApiKey.isEmpty {
            try? KeychainHelper.save(key: KeychainHelper.openAIImageApiKeyKey, value: openAIImageApiKey)
        }
    }

    private func finishOnboarding() {
        saveCurrentStep()
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
        UserDefaults.standard.set(false, forKey: "restart_onboarding_requested")
        isComplete = true
    }

    // MARK: - Load existing settings (for restart onboarding)

    private func loadExistingSettings() {
        llmProvider = KeychainHelper.load(key: KeychainHelper.llmProviderKey) ?? "lmstudio"
        openRouterApiKey = KeychainHelper.load(key: KeychainHelper.openRouterApiKeyKey) ?? ""
        openRouterModel = KeychainHelper.load(key: KeychainHelper.openRouterModelKey) ?? ""
        lmStudioBaseURL = KeychainHelper.load(key: KeychainHelper.lmStudioBaseURLKey) ?? ""
        lmStudioModel = KeychainHelper.load(key: KeychainHelper.lmStudioModelKey) ?? ""
        lmStudioDescriptionModel = KeychainHelper.load(key: KeychainHelper.lmStudioDescriptionModelKey) ?? ""
        lmStudioDescriptionBaseURL = KeychainHelper.load(key: KeychainHelper.lmStudioDescriptionBaseURLKey) ?? ""
        openAICompatibleBaseURL = KeychainHelper.load(key: KeychainHelper.openAICompatibleBaseURLKey) ?? ""
        openAICompatibleModel = KeychainHelper.load(key: KeychainHelper.openAICompatibleModelKey) ?? ""
        openAICompatibleApiKey = KeychainHelper.load(key: KeychainHelper.openAICompatibleApiKeyKey) ?? ""
        openAICompatibleReasoningEffort = KeychainHelper.load(key: KeychainHelper.openAICompatibleReasoningEffortKey) ?? ""
        // Derive the API sub-choice from what's stored
        if llmProvider == "openrouter" {
            apiChoice = "openrouter"
        } else if llmProvider == "openai_compatible" {
            apiChoice = (openAICompatibleBaseURL == Self.openCodeGoBaseURL || openAICompatibleBaseURL.isEmpty) ? "opencode" : "custom"
        }
        assistantName = KeychainHelper.load(key: KeychainHelper.assistantNameKey) ?? ""
        userName = KeychainHelper.load(key: KeychainHelper.userNameKey) ?? ""
        userContext = KeychainHelper.load(key: KeychainHelper.structuredUserContextKey) ?? ""
        telegramToken = KeychainHelper.load(key: KeychainHelper.telegramBotTokenKey) ?? ""
        chatId = KeychainHelper.load(key: KeychainHelper.telegramChatIdKey) ?? ""
        whatsappOwnerPhone = KeychainHelper.load(key: KeychainHelper.whatsappOwnerPhoneKey) ?? ""
        whatsappSelected = WhatsAppChannelService.shared.isEnabled
        // Fresh install: default to Telegram. Re-run with a WhatsApp-only
        // setup: don't force the Telegram card on.
        telegramSelected = !telegramToken.isEmpty || !whatsappSelected
        voiceTranscriptionProvider = VoiceTranscriptionProvider.fromStoredValue(
            KeychainHelper.load(key: KeychainHelper.voiceTranscriptionProviderKey)
        )
        openAITranscriptionApiKey = KeychainHelper.load(key: KeychainHelper.openAITranscriptionApiKeyKey) ?? ""
        serperApiKey = KeychainHelper.load(key: KeychainHelper.serperApiKeyKey) ?? ""
        jinaApiKey = KeychainHelper.load(key: KeychainHelper.jinaApiKeyKey) ?? ""
        geminiApiKey = KeychainHelper.load(key: KeychainHelper.geminiApiKeyKey) ?? ""
        openAIImageApiKey = KeychainHelper.load(key: KeychainHelper.openAIImageApiKeyKey) ?? ""
        imageGenerationProvider = ImageGenerationProvider.fromStoredValue(
            KeychainHelper.load(key: KeychainHelper.imageGenerationProviderKey)
        ).rawValue
    }

    // MARK: - Local Server Presets

    private func onboardingLocalPreset(from url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed.contains(":1234") { return "lmstudio" }
        if trimmed.contains(":11434") { return "ollama" }
        if trimmed.contains(":8000") { return "vllm" }
        return "custom"
    }

    private func onboardingLocalPresetURL(_ preset: String) -> String? {
        switch preset {
        case "lmstudio": return "http://localhost:1234/v1"
        case "ollama": return "http://localhost:11434/v1"
        case "vllm": return "http://localhost:8000/v1"
        default: return nil
        }
    }

    // MARK: - Telegram Test

    private func testConnection() {
        isTesting = true
        botInfo = nil
        testError = nil
        Task {
            do {
                let info = try await telegramService.getMe(token: telegramToken)
                await MainActor.run {
                    let name = info.firstName + (info.username.map { " (@\($0))" } ?? "")
                    botInfo = "Connected: \(name)"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testError = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }

    // MARK: - Skip detection for existing users

    static var shouldShowOnboarding: Bool {
        // "restart_onboarding_requested" is set by the Restart Onboarding button
        if UserDefaults.standard.bool(forKey: "restart_onboarding_requested") { return true }
        // If onboarding was completed before, don't show
        if UserDefaults.standard.bool(forKey: "onboarding_completed") { return false }
        // First launch: skip if essential fields are already configured (existing user updating the app)
        let hasToken = !(KeychainHelper.load(key: KeychainHelper.telegramBotTokenKey) ?? "").isEmpty
        let hasWhatsApp = !(KeychainHelper.load(key: KeychainHelper.whatsappOwnerPhoneKey) ?? "").isEmpty
        let hasOpenRouterKey = !(KeychainHelper.load(key: KeychainHelper.openRouterApiKeyKey) ?? "").isEmpty
        let hasOAICKey = !(KeychainHelper.load(key: KeychainHelper.openAICompatibleApiKeyKey) ?? "").isEmpty
        let hasLocalModel = !(KeychainHelper.load(key: KeychainHelper.lmStudioModelKey) ?? "").isEmpty
        if (hasToken || hasWhatsApp) && (hasOpenRouterKey || hasOAICKey || hasLocalModel) { return false }
        return true
    }
}
