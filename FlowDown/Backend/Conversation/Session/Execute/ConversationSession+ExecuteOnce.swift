//
//  ConversationSession+ExecuteOnce.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import RichEditor
import Storage

extension ConversationSession {
    func doMainInferenceOnce(
        _ currentMessageListView: MessageListView,
        _ modelID: ModelManager.ModelIdentifier,
        _ requestMessages: inout [ChatRequestBody.Message],
        _ tools: [ChatRequestBody.Tool]?,
        _ modelWillExecuteTools: Bool,
        linkedContents: [Int: URL],
        requestLinkContentIndex: @escaping (URL) -> Int
    ) async throws -> Bool {
        await requestUpdate(view: currentMessageListView)
        await currentMessageListView.loading()

        let message = appendNewMessage(role: .assistant)

        var additionalBodyField = [String: Any]()
        if let model = ModelManager.shared.cloudModel(identifier: modelID),
           URL(string: model.endpoint)?.host?.lowercased() == "openrouter.ai"
        { additionalBodyField["reasoning"] = [String: String]() }

        let stream = try await ModelManager.shared.streamingInfer(
            with: modelID,
            input: requestMessages,
            tools: tools,
            additionalBodyField: additionalBodyField
        )
        defer { self.stopThinking(for: message.id) }

        var pendingToolCalls: [ToolCallRequest] = []

        let collapseAfterReasoningComplete = ModelManager.shared.collapseReasoningSectionWhenComplete

        for try await resp in stream {
            let reasoningContent = resp.reasoningContent
            let content = resp.content
            pendingToolCalls.append(contentsOf: resp.toolCallRequests)
            message.reasoningContent = reasoningContent
            message.document = content
            if !content.isEmpty {
                stopThinking(for: message.id)
                if collapseAfterReasoningComplete { message.isThinkingFold = true }
            } else if !reasoningContent.isEmpty {
                startThinking(for: message.id)
            }
            await requestUpdate(view: currentMessageListView)
        }
        stopThinking(for: message.id)
        await requestUpdate(view: currentMessageListView)

        if collapseAfterReasoningComplete {
            message.isThinkingFold = true
            await requestUpdate(view: currentMessageListView)
        }

        if !message.document.isEmpty {
            logger.info("\(message.document)")
            message.document = fixWebReferenceIfPossible(in: message.document, with: linkedContents.mapValues(\.absoluteString))
        }
        if !message.reasoningContent.isEmpty, message.document.isEmpty {
            message.document = String(localized: "Thinking finished without output any content.")
        }

        await requestUpdate(view: currentMessageListView)
        requestMessages.append(
            .assistant(
                content: .text(message.document),
                toolCalls: pendingToolCalls.map {
                    .init(id: $0.id.uuidString, function: .init(name: $0.name, arguments: $0.args))
                }
            )
        )

        if message.document.isEmpty, message.reasoningContent.isEmpty, !modelWillExecuteTools {
            throw NSError(
                domain: "Inference Service",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "No response from model."),
                ]
            )
        }

        // 请求结束 如果没有启用工具调用就结束
        guard modelWillExecuteTools else {
            assert(pendingToolCalls.isEmpty)
            return false
        }
        pendingToolCalls = pendingToolCalls.filter {
            $0.name.lowercased() != MTWaitForNextRound().functionName.lowercased()
        }
        guard !pendingToolCalls.isEmpty else { return false }
        assert(modelWillExecuteTools)

        await requestUpdate(view: currentMessageListView)
        await currentMessageListView.loading(with: String(localized: "Utilizing tool call"))

        for request in pendingToolCalls {
            guard let tool = await ModelToolsManager.shared.findTool(for: request) else {
                throw NSError(
                    domain: "Tool Error",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "Unable to process tool request with name: \(request.name)"),
                    ]
                )
            }
            await currentMessageListView.loading(with: String(localized: "Utilizing tool: \(tool.interfaceName)"))

            // 等待一小会以避免过快执行任务用户还没看到内容
            try await Task.sleep(nanoseconds: 1 * 500_000_000)

            // 检查是否是网络搜索工具，如果是则直接执行
            if let tool = tool as? MTWebSearchTool {
                let webSearchMessage = appendNewMessage(role: .webSearch)
                let searchResult = try await tool.execute(
                    with: request.args,
                    session: self,
                    webSearchMessage: webSearchMessage,
                    anchorTo: currentMessageListView
                )
                var webAttachments: [RichEditorView.Object.Attachment] = []
                for doc in searchResult {
                    let index = requestLinkContentIndex(doc.url)
                    webAttachments.append(.init(
                        type: .text,
                        name: doc.title,
                        previewImage: .init(),
                        imageRepresentation: .init(),
                        textRepresentation: formatAsWebArchive(
                            document: doc.textDocument,
                            title: doc.title,
                            atIndex: index
                        ),
                        storageSuffix: UUID().uuidString
                    ))
                }
                await currentMessageListView.loading()

                if webAttachments.isEmpty {
                    requestMessages.append(.tool(
                        content: .text(String(localized: "Web search returned no results.")),
                        toolCallID: request.id.uuidString
                    ))
                } else {
                    requestMessages.append(.tool(
                        content: .text(webAttachments.map(\.textRepresentation).joined(separator: "\n")),
                        toolCallID: request.id.uuidString
                    ))
                }
            } else {
                // 标准工具
                guard let result = ModelToolsManager.shared.perform(
                    withTool: tool,
                    parms: request.args,
                    anchorTo: currentMessageListView
                ) else { continue }

                await requestUpdate(view: currentMessageListView)

                let toolMessage = appendNewMessage(role: .toolHint)
                toolMessage.toolStatus = .init(name: tool.interfaceName, state: 1, message: result)
                await requestUpdate(view: currentMessageListView)
                requestMessages.append(.tool(content: .text(result), toolCallID: request.id.uuidString))
            }
        }

        await requestUpdate(view: currentMessageListView)
        return true
    }
}
