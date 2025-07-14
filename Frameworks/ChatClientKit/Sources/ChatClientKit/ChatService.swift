//
//  Created by ktiays on 2025/2/12.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation

public enum ChatServiceStreamObject {
    case chatCompletionChunk(chunk: ChatCompletionChunk)
    case tool(call: ToolCallRequest)
}

public protocol ChatService: AnyObject {
    var collectedErrors: String? { get set }

    /// Initiates a non-streaming chat completion request to /v1/chat/completions.
    ///
    /// - Parameters:
    ///   - body: The request body to send to aiproxy and openai. See this reference:
    ///           https://platform.openai.com/docs/api-reference/chat/create
    /// - Returns: A ChatCompletionResponse. See this reference:
    ///            https://platform.openai.com/docs/api-reference/chat/object
    func chatCompletionRequest(body: ChatRequestBody) async throws -> ChatResponseBody

    /// Initiates a streaming chat completion request to /v1/chat/completions.
    ///
    /// - Parameters:
    ///   - body: The request body to send to aiproxy and openai. See this reference:
    ///           https://platform.openai.com/docs/api-reference/chat/create
    /// - Returns: An async sequence of completion chunks. See this reference:
    ///            https://platform.openai.com/docs/api-reference/chat/streaming
    func streamingChatCompletionRequest(
        body: ChatRequestBody
    ) async throws -> AnyAsyncSequence<ChatServiceStreamObject>
}

let REASONING_START_TOKEN: String = "<think>"
let REASONING_END_TOKEN: String = "</think>"
