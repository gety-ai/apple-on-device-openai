import Foundation
import FoundationModels
import Vapor

// MARK: - Data Models

// Define a simple structure for the AI response using @Generable
@Generable
nonisolated struct AIResponse: Sendable {
    let answer: String
    let confidence: String
}

// MARK: - Request Models

nonisolated struct ChatCompletionRequest: Content, Sendable {
    let model: String?
    let messages: [ChatMessage]
    let maxTokens: Int?
    let temperature: Double?
    let topP: Double?
    let n: Int?
    let stream: Bool?
    let stop: [String]?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let logitBias: [String: Double]?
    let user: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case n
        case stream
        case stop
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case logitBias = "logit_bias"
        case user
    }
}

// Content types for structured messages
nonisolated struct MessageContent: Content, Sendable {
    let type: String
    let text: String?
    let imageUrl: ImageUrl?
    
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
    }
}

nonisolated struct ImageUrl: Content, Sendable {
    let url: String
    let detail: String?
}

nonisolated struct ChatMessage: Content, Sendable {
    let role: String
    let content: String
    let name: String?

    init(role: String, content: String, name: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
    }
    
    // Custom decoder to handle both string and array content formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.role = try container.decode(String.self, forKey: .role)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        
        // Try to decode content as string first
        if let stringContent = try? container.decode(String.self, forKey: .content) {
            self.content = stringContent
        } else if let arrayContent = try? container.decode([MessageContent].self, forKey: .content) {
            // Extract text from structured content array
            let textParts = arrayContent.compactMap { contentItem in
                contentItem.type == "text" ? contentItem.text : nil
            }
            self.content = textParts.joined(separator: " ")
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath + [CodingKeys.content],
                    debugDescription: "Content must be either a string or an array of content objects"
                )
            )
        }
    }
    
    // Custom encoder to always encode as string
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(name, forKey: .name)
    }
    
    enum CodingKeys: String, CodingKey {
        case role
        case content
        case name
    }
}

// MARK: - Response Models

nonisolated struct ChatCompletionResponse: Content, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatCompletionChoice]

    init(id: String, object: String, created: Int, model: String, choices: [ChatCompletionChoice]) {
        self.id = id
        self.object = object
        self.created = created
        self.model = model
        self.choices = choices
    }
}

nonisolated struct ChatCompletionChoice: Content, Sendable {
    let index: Int
    let message: ChatMessage?
    let delta: ChatMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case delta
        case finishReason = "finish_reason"
    }

    init(
        index: Int, message: ChatMessage? = nil, delta: ChatMessage? = nil,
        finishReason: String? = nil
    ) {
        self.index = index
        self.message = message
        self.delta = delta
        self.finishReason = finishReason
    }
}

// MARK: - Models List Response

nonisolated struct ModelsResponse: Content, Sendable {
    let object: String
    let data: [ModelInfo]
}

nonisolated struct ModelInfo: Content, Sendable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case ownedBy = "owned_by"
    }
}

// MARK: - Server Status Response

nonisolated struct ServerStatus: Content, Sendable {
    let modelAvailable: Bool
    let reason: String
    let supportedLanguages: [String]
    let serverVersion: String
    let appleIntelligenceCompatible: Bool

    enum CodingKeys: String, CodingKey {
        case modelAvailable = "model_available"
        case reason
        case supportedLanguages = "supported_languages"
        case serverVersion = "server_version"
        case appleIntelligenceCompatible = "apple_intelligence_compatible"
    }
}

// MARK: - Error Response

nonisolated struct ErrorResponse: Content, Sendable {
    let error: ErrorDetail
}

nonisolated struct ErrorDetail: Content, Sendable {
    let message: String
    let type: String
    let param: String?
    let code: String?
}

// MARK: - Streaming Response Models

nonisolated struct ChatCompletionStreamResponse: Content, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatCompletionStreamChoice]

    init(
        id: String, object: String, created: Int, model: String,
        choices: [ChatCompletionStreamChoice]
    ) {
        self.id = id
        self.object = object
        self.created = created
        self.model = model
        self.choices = choices
    }
}

nonisolated struct ChatCompletionStreamChoice: Content, Sendable {
    let index: Int
    let delta: ChatCompletionDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }

    init(index: Int, delta: ChatCompletionDelta, finishReason: String? = nil) {
        self.index = index
        self.delta = delta
        self.finishReason = finishReason
    }
}

nonisolated struct ChatCompletionDelta: Content, Sendable {
    let role: String?
    let content: String?

    init(role: String? = nil, content: String? = nil) {
        self.role = role
        self.content = content
    }
}
