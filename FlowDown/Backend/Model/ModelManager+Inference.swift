//
//  ModelManager+Inference.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/29/25.
//

import ChatClientKit
import Foundation
import GPTEncoder
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import Storage
#if canImport(FoundationModels)
    import FoundationModels
#endif

extension ModelManager {
    // - imageProcessingFailure : "height: 1 must be larger than factor: 28"
    static let testImage: CIImage = .init(
        cgImage: UIImage(
            color: .accent,
            size: .init(width: 64, height: 64)
        ).cgImage!
    )

    func testLocalModel(_ model: LocalModel, completion: @escaping (Result<Void, Error>) -> Void) {
        guard MLX.GPU.isSupported else {
            completion(.failure(NSError(domain: "GPU", code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Your device does not support MLX."),
            ])))
            return
        }
        let task = Task.detached {
            assert(!Thread.isMainThread)
            let config = ModelConfiguration(directory: ModelManager.shared.modelContent(for: model))
            let container: ModelContainer? =
                if model.capabilities.contains(.visual) {
                    try await VLMModelFactory.shared.loadContainer(configuration: config)
                } else {
                    try await LLMModelFactory.shared.loadContainer(configuration: config)
                }
            return try await container?.perform { context in
                let input = try await context.processor.prepare(
                    input: .init(
                        messages: [
                            [
                                "role": "system",
                                "content": "Reply YES to every query.",
                            ],
                            [
                                "role": "user",
                                "content": "YES or NO",
                            ],
                        ],
                        images: model.capabilities.contains(.visual) ? [.ciImage(Self.testImage)] : []
                    )
                )
                let result: GenerateResult = try MLXLMCommon.generate(
                    input: input,
                    parameters: GenerateParameters(temperature: 0),
                    context: context
                ) { _ in .stop }
                return result.output
            }
        }
        Task.detached {
            let token = MLXChatClientQueue.shared.acquire()
            do {
                let text = try await task.value
                MLXChatClientQueue.shared.release(token: token)
                if let text, !text.isEmpty {
                    print("[*] model \(model.model_identifier) generates output for test case: \(text)")
                    completion(.success(()))
                } else {
                    completion(
                        .failure(
                            NSError(
                                domain: "Model",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to generate text.")]
                            )
                        )
                    )
                }
            } catch {
                MLXChatClientQueue.shared.release(token: token)
                if let error = error as? ModelFactoryError {
                    switch error {
                    case .unsupportedModelType:
                        completion(
                            .failure(
                                NSError(
                                    domain: "Model",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Unsupported model type.")]
                                )
                            )
                        )
                    case .unsupportedProcessorType:
                        completion(
                            .failure(
                                NSError(
                                    domain: "Model",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Unsupported processor type.")]
                                )
                            )
                        )
                    case .noModelFactoryAvailable:
                        completion(
                            .failure(
                                NSError(
                                    domain: "Model",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Unsupported model type.")]
                                )
                            )
                        )
                    case .configurationDecodingError:
                        completion(
                            .failure(
                                NSError(
                                    domain: "Model",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Unable to decode configuration.")]
                                )
                            )
                        )
                    }
                } else if let error = error as? VLMError {
                    print("[*] VLM failed to inference: \(error)")
                    completion(
                        .failure(
                            NSError(
                                domain: "Model",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: String(localized: "Unsupported.")]
                            )
                        )
                    )
                } else {
                    completion(
                        .failure(
                            NSError(
                                domain: "Model",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: String(format: String(localized: "Failed to load model: %@"), error.localizedDescription)]
                            )
                        )
                    )
                }
            }
        }
    }

    func testCloudModel(_ model: CloudModel, completion: @escaping (Result<Void, Error>) -> Void) {
        let dic: [String: Any] = [
            "model": model.model_identifier,
            "stream": true,
            "messages": [
                [
                    "role": "system",
                    "content": "Reply YES to every query.",
                ],
                [
                    "role": "user",
                    "content": "YES or NO",
                ],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dic),
              let endpoint = URL(string: model.endpoint)
        else {
            completion(
                .failure(
                    NSError(
                        domain: "Model",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid model configuration.")]
                    )
                )
            )
            return
        }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for value in model.headers {
            request.setValue(value.value, forHTTPHeaderField: value.key)
        }
        if !model.token.isEmpty { request.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = data
        URLSession.shared.dataTask(with: request) { _, resp, _ in
            guard let resp = resp as? HTTPURLResponse else {
                completion(
                    .failure(
                        NSError(
                            domain: "Model",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid response.")]
                        )
                    )
                )
                return
            }
            guard resp.statusCode == 200 else {
                completion(
                    .failure(
                        NSError(
                            domain: "Model",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: String(format: String(localized: "Invalid status code: %d"), resp.statusCode)]
                        )
                    )
                )
                return
            }
            completion(.success(()))
        }.resume()
    }

    func testAppleIntelligenceModel(completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                guard AppleIntelligenceModel.shared.isAvailable else {
                    completion(.failure(NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence not available on this device."])))
                    return
                }
                Task {
                    do {
                        let session = LanguageModelSession()
                        let prompt = "Reply YES to every query. YES or NO"
                        let response = try await session.respond(to: prompt)
                        if !response.content.isEmpty {
                            completion(.success(()))
                        } else {
                            completion(.failure(NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from Apple Intelligence."])))
                        }
                    } catch {
                        completion(.failure(error))
                    }
                }
            } else {
                completion(.failure(NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "Requires iOS 26+"])))
            }
        #else
            completion(.failure(NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "FoundationModels not available"])))
        #endif
    }
}

extension ModelManager {
    static let indicatorText = " ●"

    private func chatService(for identifier: ModelIdentifier, additionalBodyField: [String: Any]) throws -> any ChatService {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macCatalyst 26.0, *), identifier == AppleIntelligenceModel.shared.modelIdentifier {
                return AppleIntelligenceChatClient()
            }
        #endif
        if let model = cloudModel(identifier: identifier) {
            return RemoteChatClient(
                model: model.model_identifier,
                baseURL: model.endpoint,
                apiKey: model.token,
                additionalHeaders: model.headers + [
                    "HTTP-Referer": "https://flowdown.ai/",
                    "X-Title": "FlowDown",
                ],
                additionalBodyField: additionalBodyField
            )
        } else if let model = localModel(identifier: identifier) {
            return MLXChatClient(url: modelContent(for: model))
        } else {
            throw NSError(
                domain: "Model",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Model not found.")]
            )
        }
    }

    struct InferenceMessage: Hashable {
        var reasoningContent: String
        var content: String

        // a json representation for tool call
        var toolCallRequests: [ToolCallRequest]

        init(reasoningContent: String = .init(), content: String = .init(), tool: [ToolCallRequest] = []) {
            self.reasoningContent = reasoningContent
            self.content = content
            toolCallRequests = tool
        }
    }

    func prepareRequestBody(
        modelID: ModelIdentifier,
        messages: [ChatRequestBody.Message]
    ) throws -> [ChatRequestBody.Message] {
        var messages = messages
        if let model = cloudModel(identifier: modelID) {
            // this model requires developer mode to work
            if model.capabilities.contains(.developerRole) {
                messages = messages.map { message in
                    switch message {
                    case let .system(content, name):
                        .developer(content: content, name: name)
                    default:
                        message
                    }
                }
            }
        }
        return messages
    }

    func infer(
        with modelID: ModelIdentifier,
        maxCompletionTokens: Int? = nil,
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]? = nil,
        additionalBodyField: [String: Any] = [:]
    ) async throws -> InferenceMessage {
        let client = try chatService(for: modelID, additionalBodyField: additionalBodyField)
        let response = try await client.chatCompletionRequest(
            body: .init(
                messages: prepareRequestBody(modelID: modelID, messages: input),
                maxCompletionTokens: maxCompletionTokens,
                temperature: .init(ModelManager.shared.temperature),
                tools: tools
            )
        )
        let message = response.choices.first?.message
        let reasoning = message?.reasoning ?? .init()
        let reasoningContent = message?.reasoningContent ?? .init()

        let finalReasoning = if reasoning == reasoningContent, !reasoning.isEmpty {
            reasoning
        } else {
            [reasoning, reasoningContent].filter { !$0.isEmpty }.joined()
        }

        return .init(
            reasoningContent: finalReasoning,
            content: message?.content ?? .init(),
            // TODO: IMPL
            tool: []
        )
    }

    func streamingInfer(
        with modelID: ModelIdentifier,
        maxCompletionTokens: Int? = nil,
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]? = nil,
        additionalBodyField: [String: Any] = [:]
    ) async throws -> AsyncThrowingStream<InferenceMessage, any Error> {
        let client = try chatService(for: modelID, additionalBodyField: additionalBodyField)
        client.collectedErrors = nil

        let stream = try await client.streamingChatCompletionRequest(
            body: .init(
                messages: prepareRequestBody(modelID: modelID, messages: input),
                maxCompletionTokens: maxCompletionTokens,
                temperature: .init(ModelManager.shared.temperature),
                tools: tools
            )
        ).compactMap { streamObject -> InferenceMessage in
            var msg = InferenceMessage()
            switch streamObject {
            case let .chatCompletionChunk(chunk):
                let delta = chunk.choices.first?.delta
                let reasoning = delta?.reasoning ?? .init()
                let reasoningContent = delta?.reasoningContent ?? .init()

                msg.reasoningContent = if reasoning == reasoningContent, !reasoning.isEmpty {
                    reasoning
                } else {
                    [reasoning, reasoningContent].filter { !$0.isEmpty }.joined()
                }
                msg.content = delta?.content ?? .init()
            case let .tool(call):
                msg.toolCallRequests = [call]
            }
            return msg
        }
        var responseContent: InferenceMessage = .init()
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var collectedToolCalls: [ToolCallRequest] = []

                    for try await chunk in stream {
                        //
                        // we assuming server sent us delta content with 0.5s each time
                        // so make sure all of our content is shown before that
                        //
                        // on average 2ms is required to display the text content
                        // and by running at 120fps we need to update no longer then 8ms
                        //

                        // by calculating for 10ms each time, 0.5s to show all, max update is 50 times
                        var counter = 0

                        // 10ms
                        func sleepOnce() async {
                            try? await Task.sleep(nanoseconds: 10 * 1_000_000)
                            counter = 0
                        }

                        let newReasoningContentLength = chunk.reasoningContent.count
                        let newReasoningContentChunkSize = max(1, newReasoningContentLength / 50)
                        counter = 0

                        for char in chunk.reasoningContent {
                            responseContent.reasoningContent += String(char)
                            counter += 1
                            if counter > newReasoningContentChunkSize {
                                continuation.yield(.init(
                                    reasoningContent: (responseContent.reasoningContent + Self.indicatorText)
                                        .trimmingCharacters(in: .whitespacesAndNewlines),
                                    content: responseContent.content
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                ))
                                await sleepOnce()
                            }
                        }

                        let newContentLength = chunk.content.count
                        let newContentChunkSize = max(1, newContentLength / 50)
                        counter = 0

                        for char in chunk.content {
                            responseContent.content += String(char)
                            counter += 1
                            if counter > newContentChunkSize {
                                continuation.yield(.init(
                                    reasoningContent: responseContent.reasoningContent
                                        .trimmingCharacters(in: .whitespacesAndNewlines),
                                    content: (responseContent.content + Self.indicatorText)
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                ))
                                await sleepOnce()
                            }
                        }

                        collectedToolCalls.append(contentsOf: chunk.toolCallRequests)
                    }

                    let _reasoningContent = responseContent.reasoningContent
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    var _responseContent = responseContent.content
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    for terminator in ChatClientConstants.additionalTerminatingTokens {
                        while _responseContent.hasSuffix(terminator) {
                            _responseContent.removeLast(terminator.count)
                        }
                    }

                    let final = InferenceMessage(
                        reasoningContent: _reasoningContent,
                        content: _responseContent,
                        tool: collectedToolCalls
                    )
                    continuation.yield(final)

                    // upon finish, check if any thing was returned
                    if final.content.isEmpty,
                       final.reasoningContent.isEmpty,
                       final.toolCallRequests.isEmpty
                    {
                        // if not, collect the error if we had any
                        if let error = client.collectedErrors {
                            throw NSError(
                                domain: String(localized: "Inference Service"),
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: error]
                            )
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func calculateEstimateTokensUsingCommonEncoder(
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]
    ) -> Int {
        assert(!Thread.isMainThread)

        func text(
            _ content: ChatRequestBody.Message.MessageContent<String, [String]>
        ) -> String {
            switch content {
            case let .text(text):
                text
            case let .parts(strings):
                strings.joined(separator: "\n")
            }
        }

        // will pass to encoder later
        var estimatedInferenceText = ""

        // when processing images, assume 1 image = 512 tokens
        var estimatedAdditionalTokens = 0

        for message in input {
            switch message {
            case let .assistant(content, name, refusal, calls):
                estimatedInferenceText += "role: assistant\n"
                if let content { estimatedInferenceText += text(content) }
                if let name { estimatedInferenceText += "name: \(name)\n" }
                if let refusal { estimatedInferenceText += "refusal: \(refusal)\n" }
                if let calls { estimatedInferenceText += "calls: \(calls)\n" }
            case let .system(content, name):
                estimatedInferenceText += "role: assistant\n"
                estimatedInferenceText += text(content)
                if let name { estimatedInferenceText += "name: \(name)\n" }
            case let .user(content, name):
                estimatedInferenceText += "role: user\n"
                if let name { estimatedInferenceText += "name: \(name)\n" }
                switch content {
                case let .text(text):
                    estimatedInferenceText += text
                case let .parts(contentParts):
                    for part in contentParts {
                        switch part {
                        case let .text(text): estimatedInferenceText += text
                        case .imageURL: estimatedAdditionalTokens += 512
                        }
                    }
                }
            case let .developer(content, name):
                estimatedInferenceText += "role: developer\n"
                estimatedInferenceText += text(content)
                if let name { estimatedInferenceText += "name: \(name)\n" }
            case let .tool(content, id):
                estimatedInferenceText += "role: tool \(id)\n"
                estimatedInferenceText += text(content)
            }
        }

        if !tools.isEmpty {
            let encoder = JSONEncoder()
            if let toolText = try? encoder.encode(tools),
               let toolString = String(data: toolText, encoding: .utf8)
            {
                estimatedInferenceText += "tools: \(toolString)\n"
            } else { assertionFailure() }
        }

        let encoder = GPTEncoder()
        let tokens = encoder.encode(text: estimatedInferenceText)

        return tokens.count + estimatedAdditionalTokens
    }
}
