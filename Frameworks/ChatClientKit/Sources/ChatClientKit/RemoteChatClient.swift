//
//  Created by ktiays on 2025/2/12.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import RegexBuilder
import ServerEvent
import Tokenizers

open class RemoteChatClient: ChatService {
    private let session = URLSession.shared

    /// The ID of the model to use.
    ///
    /// The required section should be in alphabetical order.
    public let model: String
    public var baseURL: String?
    public var path: String?
    public var apiKey: String?

    public enum Error: Swift.Error {
        case invalidURL
        case invalidApiKey
        case invalidData
    }

    public var collectedErrors: String?

    public var additionalHeaders: [String: String] = [:]
    public var additionalField: [String: Any] = [:]

    public init(
        model: String,
        baseURL: String? = nil,
        path: String? = nil,
        apiKey: String? = nil,
        additionalHeaders: [String: String] = [:],
        additionalBodyField: [String: Any] = [:]
    ) {
        self.model = model
        self.baseURL = baseURL
        self.path = path
        self.apiKey = apiKey
        self.additionalHeaders = additionalHeaders
        additionalField = additionalBodyField
    }

    public func chatCompletionRequest(body: ChatRequestBody) async throws -> ChatResponseBody {
        var body = body
        body.model = model
        body.stream = false
        body.streamOptions = nil
        let request = try request(for: body, additionalField: additionalField)
        let (data, _) = try await session.data(for: request)
        var response = try JSONDecoder().decode(ChatResponseBody.self, from: data)
        response.choices = response.choices.map { choice in
            var choice = choice
            choice.message = extractReasoningContent(from: choice.message)
            return choice
        }
        return response
    }

    private func processAccumulatedContent(_ accumulatedContent: String) -> ChatCompletionChunk? {
        guard let (beforeContent, reasoningContent, afterContent) = extractOutermostThinkBlock(from: accumulatedContent) else {
            return nil
        }

        var deltas = [ChatCompletionChunk.Choice.Delta]()

        if !beforeContent.isEmpty {
            deltas.append(.init(content: beforeContent))
        }

        if !reasoningContent.isEmpty {
            deltas.append(.init(reasoningContent: reasoningContent))
        }

        if !afterContent.isEmpty {
            deltas.append(.init(content: afterContent))
        }

        return deltas.isEmpty ? nil : .init(choices: deltas.map { .init(delta: $0) })
    }

    private func finalizeAccumulatedContent(_ accumulatedContent: String) -> ChatCompletionChunk? {
        if let processedResponse = processAccumulatedContent(accumulatedContent) {
            processedResponse
        } else {
            accumulatedContent.isEmpty ? nil : .init(choices: [.init(delta: .init(content: accumulatedContent))])
        }
    }

    private func extractOutermostThinkBlock(from content: String) -> (beforeContent: String, reasoningContent: String, afterContent: String)? {
        guard let startRange = content.range(of: REASONING_START_TOKEN) else {
            return nil
        }

        let beforeContent = String(content[..<startRange.lowerBound])
        let remainingAfterStart = String(content[startRange.upperBound...])

        guard let endRange = remainingAfterStart.range(of: REASONING_END_TOKEN) else {
            return nil
        }

        let reasoningContent = String(remainingAfterStart[..<endRange.lowerBound])
        let afterContent = String(remainingAfterStart[endRange.upperBound...])

        return (
            beforeContent.trimmingCharacters(in: .whitespacesAndNewlines),
            reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines),
            afterContent.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public func streamingChatCompletionRequest(
        body: ChatRequestBody
    ) async throws -> AnyAsyncSequence<ChatServiceStreamObject> {
        var body = body
        body.model = model
        body.stream = true

        // streamOptions is not supported when running up on cohere api
        // body.streamOptions = .init(includeUsage: true)
        let request = try request(for: body, additionalField: additionalField)
        logger.info("starting streaming request with \(body.messages.count) messages")

        let stream = AsyncStream<ChatServiceStreamObject> { continuation in
            Task.detached {
                // Extracts or preserves the reasoning content within a `ChoiceMessage`.

                var canDecodeReasoningContent = true
                var accumulatedContent = ""
                let toolCallCollector: ToolCallCollector = .init()

                let eventSource = EventSource()
                let dataTask = eventSource.dataTask(for: request)

                for await event in dataTask.events() {
                    switch event {
                    case .open:
                        logger.info("connection was opened.")
                    case let .error(error):
                        logger.error("received an error: \(error)")
                        self.collect(error: error)
                    case let .event(event):
                        guard let data = event.data?.data(using: .utf8) else {
                            continue
                        }
                        if let text = String(data: data, encoding: .utf8) {
                            if text.lowercased() == "[DONE]".lowercased() {
                                print("[*] received done from upstream")
                                continue
                            }
                        }
                        do {
                            var response = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
                            let reasoningContent = [
                                response.choices.map(\.delta).compactMap(\.reasoning),
                                response.choices.map(\.delta).compactMap(\.reasoningContent),
                            ].flatMap(\.self)
                            let content = response.choices.map(\.delta).compactMap(\.content)

                            if canDecodeReasoningContent { canDecodeReasoningContent = reasoningContent.isEmpty }

                            if canDecodeReasoningContent {
                                let newContent = content.joined()
                                accumulatedContent += newContent

                                // to avoid looooong reasoning
                                if accumulatedContent.count > 50000 {
                                    let truncated = String(accumulatedContent.suffix(40000))
                                    // Avoid splitting incomplete <think> tags
                                    if let lastStart = truncated.range(of: REASONING_START_TOKEN, options: .backwards),
                                       !truncated[lastStart.upperBound...].contains(REASONING_END_TOKEN)
                                    {
                                        accumulatedContent = String(truncated[..<lastStart.lowerBound])
                                    } else {
                                        accumulatedContent = truncated
                                    }
                                }

                                let processedResponse = self.processAccumulatedContent(accumulatedContent)
                                if let processedResponse {
                                    response = processedResponse
                                    accumulatedContent = ""
                                } else {
                                    continue
                                }
                            }

                            for delta in response.choices {
                                for toolDelta in delta.delta.toolCalls ?? [] {
                                    toolCallCollector.submit(delta: toolDelta)
                                }
                            }

                            continuation.yield(.chatCompletionChunk(chunk: response))
                        } catch {
                            if let text = String(data: data, encoding: .utf8) {
                                logger.log("text content associated with this error \(text)")
                            }
                            self.collect(error: error)
                        }
                        if let decodeError = self.extractError(fromInput: data) {
                            self.collect(error: decodeError)
                        }
                    case .closed:
                        logger.info("connection was closed.")
                    }
                }

                if !accumulatedContent.isEmpty {
                    if let finalResponse = self.finalizeAccumulatedContent(accumulatedContent) {
                        continuation.yield(.chatCompletionChunk(chunk: finalResponse))
                    }
                }

                toolCallCollector.finalizeCurrentDeltaContent()
                for call in toolCallCollector.pendingRequests {
                    continuation.yield(.tool(call: call))
                }
                continuation.finish()
            }
        }
        return stream.eraseToAnyAsyncSequence()
    }

    private func collect(error: Swift.Error) {
        if let error = error as? EventSourceError {
            switch error {
            case .undefinedConnectionError:
                collectedErrors = String(localized: "Unable to connect to the server.", bundle: .module)
            case let .connectionError(statusCode, response):
                if let decodedError = extractError(fromInput: response) {
                    collectedErrors = decodedError.localizedDescription
                } else {
                    collectedErrors = String(localized: "Connection error: \(statusCode)", bundle: .module)
                }
            case .alreadyConsumed:
                assertionFailure()
            }
            return
        }
        collectedErrors = error.localizedDescription
        logger.error("collected error: \(error.localizedDescription)")
    }

    private func extractError(fromInput input: Data) -> Swift.Error? {
        let dic = try? JSONSerialization.jsonObject(with: input, options: []) as? [String: Any]
        guard let dic else { return nil }

        let errorDic = dic["error"] as? [String: Any]
        guard let errorDic else { return nil }

        var message = errorDic["message"] as? String ?? String(localized: "Unknown Error", bundle: .module)
        let code = errorDic["code"] as? Int ?? 403

        // check for metadata property, read there if find
        if let metadata = errorDic["metadata"] as? [String: Any],
           let metadataMessage = metadata["message"] as? String
        {
            message += " \(metadataMessage)"
        }

        return NSError(domain: String(localized: "Server Error"), code: code, userInfo: [
            NSLocalizedDescriptionKey: String(localized: "Server returns an error: \(code) \(message)", bundle: .module),
        ])
    }

    private func request(for body: ChatRequestBody, additionalField: [String: Any] = [:]) throws -> URLRequest {
        guard let baseURL else {
            throw Error.invalidURL
        }
        guard let apiKey else {
            throw Error.invalidApiKey
        }

        var path = path ?? ""
        if !path.isEmpty, !path.starts(with: "/") {
            path = "/\(path)"
        }

        guard var urlComponents = URLComponents(string: baseURL),
              let pathComponents = URLComponents(string: path)
        else {
            throw Error.invalidURL
        }

        urlComponents.path += pathComponents.path
        urlComponents.queryItems = pathComponents.queryItems

        guard let url = urlComponents.url else {
            throw Error.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        for (key, value) in additionalHeaders {
            request.addValue(value, forHTTPHeaderField: key)
        }

        if !additionalField.isEmpty {
            var originalDictionary: [String: Any] = [:]
            if let data = request.httpBody,
               let dic = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                originalDictionary = dic
            }
            for (key, value) in additionalField {
                originalDictionary[key] = value
            }
            request.httpBody = try JSONSerialization.data(
                withJSONObject: originalDictionary,
                options: []
            )
        }

        return request
    }

    /// Extracts or preserves the reasoning content within a `ChoiceMessage`.
    ///
    /// This function inspects the provided `ChoiceMessage` to determine if it already contains
    /// a `reasoningContent` value, indicating compliance with the expected API format. If present,
    /// the original `ChoiceMessage` is returned unchanged. Otherwise, it attempts to extract the text
    /// enclosed within `<think>` and `</think>` tags from the `content` property,
    /// creating a new `ChoiceMessage` with the extracted content assigned to `reasoningContent`.
    ///
    /// - Parameter choice: The `ChoiceMessage` object to process.
    /// - Returns: A `ChoiceMessage` object, either the original if `reasoningContent` exists, or a new one
    ///            with extracted reasoning content if applicable; returns the original if extraction fails.
    private func extractReasoningContent(from choice: ChoiceMessage) -> ChoiceMessage {
        if choice.reasoning?.isEmpty == false || choice.reasoningContent?.isEmpty == false {
            return choice
        }

        guard let content = choice.content else {
            return choice
        }

        guard let (beforeContent, reasoningContent, afterContent) = extractOutermostThinkBlock(from: content) else {
            return choice
        }

        var newChoice = choice
        newChoice.content = beforeContent + afterContent
        newChoice.reasoningContent = reasoningContent
        return newChoice
    }
}

class ToolCallCollector {
    var functionName: String = ""
    var functionArguments: String = ""
    var currentId: Int?
    var pendingRequests: [ToolCallRequest] = []

    func submit(delta: ChatCompletionChunk.Choice.Delta.ToolCall) {
        guard let function = delta.function else { return }

        if currentId != delta.index { finalizeCurrentDeltaContent() }
        currentId = delta.index

        if let name = function.name, !name.isEmpty {
            functionName.append(name)
        }
        if let arguments = function.arguments {
            functionArguments.append(arguments)
        }
    }

    func finalizeCurrentDeltaContent() {
        guard !functionName.isEmpty || !functionArguments.isEmpty else {
            return
        }
        let call = ToolCallRequest(name: functionName, args: functionArguments)
        print(call)
        pendingRequests.append(call)
        functionName = ""
        functionArguments = ""
    }
}
