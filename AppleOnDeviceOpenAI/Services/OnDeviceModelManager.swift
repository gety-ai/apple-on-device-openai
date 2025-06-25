import Foundation
import FoundationModels
import Vapor

// MARK: - Apple Intelligence Manager

/// Manager for Apple Intelligence on-device language model
actor OnDeviceModelManager {
    private let model: SystemLanguageModel

    init() {
        self.model = SystemLanguageModel.default
    }

    /// Check if the model is available
    func isModelAvailable() -> (available: Bool, reason: String?) {
        let availability = model.availability

        switch availability {
        case .available:
            return (true, nil)

        case .unavailable(let reason):
            let reasonString: String
            switch reason {
            case .deviceNotEligible:
                reasonString =
                    "Device not eligible for Apple Intelligence. Supported devices: iPhone 15 Pro/Pro Max or newer, iPad with M1 chip or newer, Mac with Apple Silicon"

            case .appleIntelligenceNotEnabled:
                reasonString =
                    "Apple Intelligence not enabled. Enable it in Settings > Apple Intelligence & Siri"

            case .modelNotReady:
                reasonString =
                    "AI model not ready. Models are downloaded automatically based on network status, battery level, and system load. Please wait and try again later."

            @unknown default:
                reasonString = "Unknown availability issue"
            }
            return (false, reasonString)

        @unknown default:
            return (false, "Unknown availability status")
        }
    }

    /// Get supported languages
    func getSupportedLanguages() -> [String] {
        let languages = model.supportedLanguages

        return languages.compactMap { language -> String? in
            let locale = Locale(identifier: language.maximalIdentifier)

            // Get the display name in the current locale
            if let displayName = locale.localizedString(forIdentifier: language.maximalIdentifier) {
                return displayName
            }

            // Fallback to language code if display name is not available
            return language.languageCode?.identifier
        }.sorted()
    }

    /// Convert chat messages to transcript entries
    func convertMessagesToTranscript(_ messages: [ChatMessage]) -> [Transcript.Entry] {
        var entries: [Transcript.Entry] = []

        // Process all messages in order
        for message in messages {
            let textSegment = Transcript.TextSegment(content: message.content)

            switch message.role.lowercased() {
            case "system":
                // Convert system messages to instructions
                let instructions = Transcript.Instructions(
                    segments: [.text(textSegment)],
                    toolDefinitions: []
                )
                entries.append(.instructions(instructions))

            case "user":
                // Convert user messages to prompts
                let prompt = Transcript.Prompt(
                    segments: [.text(textSegment)]
                )
                entries.append(.prompt(prompt))

            case "assistant":
                // Convert assistant messages to responses
                let response = Transcript.Response(
                    assetIDs: [],
                    segments: [.text(textSegment)]
                )
                entries.append(.response(response))

            default:
                // Treat unknown roles as user messages
                let prompt = Transcript.Prompt(
                    segments: [.text(textSegment)]
                )
                entries.append(.prompt(prompt))
            }
        }

        return entries
    }

    /// Generate a response for the given messages with conversation context
    func generateResponse(
        for messages: [ChatMessage], temperature: Double? = nil, maxTokens: Int? = nil
    ) async throws -> String {
        // Check availability first
        let (available, reason) = isModelAvailable()
        guard available else {
            throw Abort(
                .serviceUnavailable, reason: reason ?? "Apple Intelligence model is not available")
        }

        guard !messages.isEmpty else {
            throw Abort(.badRequest, reason: "No messages provided")
        }

        // Get the last message as the current prompt
        let lastMessage = messages.last!
        let currentPrompt = lastMessage.content

        // Convert previous messages (excluding the last one) to transcript
        let previousMessages = messages.count > 1 ? Array(messages.dropLast()) : []
        let transcriptEntries = convertMessagesToTranscript(previousMessages)

        // Create transcript with conversation history
        let transcript = Transcript()

        // Create new session with the conversation transcript
        let session = LanguageModelSession(
            model: model
        )

        do {
            // Create generation options if temperature is specified
            var options = GenerationOptions()
            if let temp = temperature {
                options = GenerationOptions(temperature: temp, maximumResponseTokens: maxTokens)
            } else if let maxTokens = maxTokens {
                options = GenerationOptions(maximumResponseTokens: maxTokens)
            }

            // Generate response using the current prompt
            let response = try await session.respond(
                to: currentPrompt,
                options: options
            )

            let content = response.content
            return content
        } catch {
            throw Abort(
                .internalServerError,
                reason: "Error generating response: \(error.localizedDescription)")
        }
    }

    /// Generate a response for a single prompt (for backward compatibility)
    func generateResponse(for prompt: String, temperature: Double? = nil, maxTokens: Int? = nil)
        async throws -> String
    {
        let messages = [ChatMessage(role: "user", content: prompt)]
        return try await generateResponse(
            for: messages, temperature: temperature, maxTokens: maxTokens)
    }
}

// Global instance of the Apple Intelligence manager
let aiManager = OnDeviceModelManager()
