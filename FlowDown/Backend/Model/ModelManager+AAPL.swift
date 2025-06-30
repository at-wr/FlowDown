//
//  ModelManager+AAPL.swift
//  FlowDown
//
//  Created by Alan Ye on 6/30/25.
//

import Foundation
import UIKit
import ChatClientKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Apple Intelligence Model

/// Represents the Apple Intelligence on-device model (iOS 26+ only).
@available(iOS 26.0, macCatalyst 26.0, *)
final class AppleIntelligenceModel {
    static let shared = AppleIntelligenceModel()
    /// Returns true if the device supports Apple Intelligence and the model is available.
    var isAvailable: Bool {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            #if canImport(FoundationModels)
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return true
            default:
                return false
            }
            #else
            return false
            #endif
        } else {
            return false
        }
    }
    var availabilityStatus: String {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            #if canImport(FoundationModels)
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return "Available"
            case .unavailable(.deviceNotEligible):
                return "Device Not Eligible"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence Not Enabled"
            case .unavailable(.modelNotReady):
                return "Model Not Ready"
            case .unavailable(let other):
                return "Unavailable: \(other)"
            }
            #else
            return "Not Supported"
            #endif
        } else {
            return "Requires iOS 26+"
        }
    }
    var modelDisplayName: String {
        return "Apple Intelligence"
    }
    var modelIdentifier: String {
        return "apple.intelligence.ondevice"
    }
    var modelInfo: [String: String] {
        return [
            "identifier": modelIdentifier,
            "displayName": modelDisplayName,
            "status": availabilityStatus
        ]
    }
}

// MARK: - Chat Client

class AppleIntelligenceChatClient: ChatService {
    // MARK: - ChatService Protocol
    var collectedErrors: String?

    func chatCompletionRequest(body: ChatRequestBody) async throws -> ChatResponseBody {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            // instructions (first .system message)
            let instructions = body.messages.compactMap { message -> String? in
                if case let .system(content, _) = message {
                    return extractTextFromSystem(content)
                }
                return nil
            }.first ?? ""
            // prompt (last .user message)
            let prompt = body.messages.reversed().compactMap { message -> String? in
                if case let .user(content, _) = message {
                    return extractTextFromUser(content)
                }
                return nil
            }.first ?? ""
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let message = ChatChoice(
                finishReason: "stop",
                message: ChoiceMessage(
                    content: response.content,
                    reasoning: nil,
                    reasoningContent: nil,
                    role: "assistant",
                    toolCalls: nil
                )
            )
            return ChatResponseBody(
                choices: [message],
                created: Int(Date().timeIntervalSince1970),
                model: "apple-intelligence",
                usage: nil,
                systemFingerprint: nil
            )
        } else {
            throw NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "Requires iOS 26+"])
        }
        #else
        throw NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "FoundationModels not available"])
        #endif
    }

    func streamingChatCompletionRequest(body: ChatRequestBody) async throws -> AnyAsyncSequence<ChatServiceStreamObject> {
        let response = try await chatCompletionRequest(body: body)
        return AnyAsyncSequence(AsyncStream<ChatServiceStreamObject> { continuation in
            for choice in response.choices {
                let chunk = ChatCompletionChunk(
                    choices: [
                        ChatCompletionChunk.Choice(
                            delta: ChatCompletionChunk.Choice.Delta(
                                content: choice.message.content,
                                reasoning: choice.message.reasoning,
                                reasoningContent: choice.message.reasoningContent,
                                refusal: nil,
                                role: choice.message.role,
                                toolCalls: nil
                            ),
                            finishReason: choice.finishReason,
                            index: nil
                        )
                    ],
                    created: response.created,
                    id: nil,
                    model: response.model,
                    serviceTier: nil,
                    systemFingerprint: response.systemFingerprint,
                    usage: response.usage
                )
                continuation.yield(.chatCompletionChunk(chunk: chunk))
            }
            continuation.finish()
        })
    }
}

// MARK: - Helpers

private func extractTextFromSystem(_ content: ChatRequestBody.Message.MessageContent<String, [String]>) -> String {
    switch content {
    case let .text(text):
        return text
    case let .parts(parts):
        return parts.joined(separator: " ")
    }
}
private func extractTextFromUser(_ content: ChatRequestBody.Message.MessageContent<String, [ChatRequestBody.Message.ContentPart]>) -> String {
    switch content {
    case let .text(text):
        return text
    case let .parts(parts):
        return parts.compactMap { part in
            if case let .text(text) = part { return text } else { return nil }
        }.joined(separator: " ")
    }
}
