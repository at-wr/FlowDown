//
//  ConversationSession+Execute.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/25/25.
//

import AlertController
import ChatClientKit
import RichEditor
import ScrubberKit
import Storage
import UIKit

extension ConversationSession {
    func doInfere(
        modelID: ModelManager.ModelIdentifier,
        currentMessageListView: MessageListView,
        inputObject: RichEditorView.Object,
        completion: @escaping () -> Void
    ) {
        cancelCurrentTask { [self] in
            print("[*] do infere called: \(id)")
            print("    - chat - \(ModelManager.shared.modelName(identifier: models.chat))")
            print("    - task - \(ModelManager.shared.modelName(identifier: models.auxiliary))")
            print("    - view - \(ModelManager.shared.modelName(identifier: models.visualAuxiliary))")

            var backgroundTask: UIBackgroundTaskIdentifier = .invalid
            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                if let id = self?.id {
                    print("[-] background task expired for conversation: \(id)")
                } else {
                    print("[-] background task expired for unknown conversation")
                }
                self?.currentTask?.cancel()
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }

            currentTask = Task {
                defer {
                    if backgroundTask != .invalid {
                        let finalBackgroundTask = backgroundTask
                        backgroundTask = .invalid
                        DispatchQueue.main.async {
                            UIApplication.shared.endBackgroundTask(finalBackgroundTask)
                        }
                    }
                }
                await requestUpdate(view: currentMessageListView)
                await doInfereExecute(
                    modelID: modelID,
                    currentMessageListView: currentMessageListView,
                    inputObject: inputObject
                )
                self.currentTask = nil
                await MainActor.run { completion() }
            }
        }
    }

    func requestUpdate(view: MessageListView) async {
        await view.stopLoading()
        notifyMessagesDidChange()
    }

    func saveIfNeeded(_ object: RichEditorView.Object) {
        if case let .bool(value) = object.options[.ephemeral], !value {
            save()
        }
    }

    private nonisolated func doInfereExecute(
        modelID: ModelManager.ModelIdentifier,
        currentMessageListView: MessageListView,
        inputObject: RichEditorView.Object
    ) async {
        var object = inputObject

        // MARK: - 推理前准备

        let modelName = ModelManager.shared.modelName(identifier: modelID)
        let modelCapabilities = ModelManager.shared.modelCapabilities(identifier: modelID)
        let modelContextLength = ModelManager.shared.modelContextLength(identifier: modelID)
        var modelWillExecuteTools = false
        var modelWillGoSearchWeb = false
        if case let .bool(value) = object.options[.tools], value {
            assert(modelCapabilities.contains(.tool))
            modelWillExecuteTools = true
        }
        if case let .bool(value) = object.options[.browsing], value {
            modelWillGoSearchWeb = true
        }

        assert(models.chat != nil)

        // prevent screen lock
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }

        saveIfNeeded(object)

        var tools: [ModelTool] = []
        if modelWillExecuteTools {
            tools.append(contentsOf: ModelToolsManager.shared.enabledTools)
            if modelWillGoSearchWeb {
                // enabled by default
                // tools.append(MTWebSearchTool())
            } else {
                // but if user disabled web search here, remove it from available tools
                tools = tools.filter { !($0 is MTWebSearchTool) }
            }
        }

        // MARK: - 上下文转译到请求体 不包含当前编辑框中的附件

        var requestMessages: [ChatRequestBody.Message] = []
        buildInitialRequestMessages(&requestMessages, modelCapabilities)

        do {
            try await doInfereExecuteCore(
                currentMessageListView,
                &object,
                modelCapabilities,
                &requestMessages,
                modelName,
                modelWillExecuteTools,
                // keep it nil otherwise upstream will complaint about it
                tools.isEmpty ? nil : tools.map(\.definition),
                modelContextLength,
                modelID
            )
            saveIfNeeded(object)
        } catch {
            logger.error("\(error.localizedDescription)")
            let message = appendNewMessage(role: .assistant)
            message.document = "*\(error.localizedDescription)*"
            await requestUpdate(view: currentMessageListView)
            await requestUpdate(view: currentMessageListView)
        }

        stopThinkingForAll()
        for message in messages {
            if message.document.hasSuffix(ModelManager.indicatorText) {
                message.document.removeLast(ModelManager.indicatorText.count)
            }
            if message.reasoningContent.hasSuffix(ModelManager.indicatorText) {
                message.reasoningContent.removeLast(ModelManager.indicatorText.count)
            }
        }

        await requestUpdate(view: currentMessageListView)
        saveIfNeeded(object)

        await requestUpdate(view: currentMessageListView)
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
    }

    func requestLinkContentIndex(_ url: URL) -> Int {
        assert(!Thread.isMainThread)
        let index = linkedContents.count + 1
        linkedContents[index] = url
        print("[*] request link content index: \(index) for url: \(url)")
        return index
    }

    private func doInfereExecuteCore(
        _ currentMessageListView: MessageListView,
        _ object: inout RichEditorView.Object,
        _ modelCapabilities: Set<ModelCapabilities>,
        _ requestMessages: inout [ChatRequestBody.Message],
        _ modelName: String,
        _ modelWillExecuteTools: Bool,
        _ tools: [ChatRequestBody.Tool]?,
        _ modelContextLength: Int,
        _ modelID: ModelManager.ModelIdentifier
    ) async throws {
        try checkCancellation()
        await currentMessageListView.loading()

        // MARK: - 添加用户的消息到储存框架

        let userMessage = appendNewMessage(role: .user)
        userMessage.document = object.text
        addAttachments(object.attachments, to: userMessage)
        await requestUpdate(view: currentMessageListView)

        // MARK: - 添加 Attachment 数据到持久化内容

        if case let .bool(value) = object.options[.ephemeral], !value {
            updateAttachments(object.attachments, for: userMessage)
        }
        saveIfNeeded(object)

        // MARK: - 预处理图片信息提取

        try checkCancellation()
        try await preprocessAttachments(
            &object,
            modelCapabilities.contains(.visual),
            currentMessageListView,
            userMessage
        )
        saveIfNeeded(object)

        // MARK: - 开始提取搜索关键词 爬取网页

        try checkCancellation()
        try await preprocessSearchQueries(
            currentMessageListView,
            &object,
            requestLinkContentIndex: requestLinkContentIndex
        )
        saveIfNeeded(object)

        // MARK: - 添加这次的附件

        if !object.attachments.isEmpty {
            let attachmentMessages = makeMessageFromAttachments(
                object.attachments,
                isModelSupportsVision: modelCapabilities.contains(.visual)
            )
            requestMessages.append(contentsOf: attachmentMessages)
            saveIfNeeded(object)
        }

        // MARK: - 添加最新的系统提示

        injectNewSystemCommand(&requestMessages, modelName, modelWillExecuteTools, object)

        // MARK: - 删除超出上下文长度限制的消息

        try checkCancellation()
        if try removeOutOfContextContents(&requestMessages, tools, modelContextLength) {
            let hint = appendNewMessage(role: .hint)
            hint.document = String(
                localized: "Some messages have been removed to fit the model context length.")
            await requestUpdate(view: currentMessageListView)
        }

        // MARK: - 挪动系统提示词到最前面

        moveSystemMessagesToFront(&requestMessages)

        // MARK: - 开始循环调用接口

        try checkCancellation()
        saveIfNeeded(object)

        var shouldContinue = false
        repeat {
            shouldContinue = try await doMainInferenceOnce(
                currentMessageListView,
                modelID,
                &requestMessages,
                tools,
                modelWillExecuteTools,
                linkedContents: linkedContents,
                requestLinkContentIndex: requestLinkContentIndex
            )
            saveIfNeeded(object)
        } while shouldContinue

        await requestUpdate(view: currentMessageListView)

        print("[*] inference done")
        
        // Force sync all assistant messages created during inference
        // This bypasses debouncing to ensure immediate CloudKit sync
        let assistantMessages = messages.filter { $0.role == .assistant }
        for message in assistantMessages {
            if abs(message.lastModified.timeIntervalSinceNow) < 30 { // Modified within last 30 seconds
                CloudKitSyncManager.shared.forceSyncLocalChange(for: message, changeType: .update)
            }
        }

        // MARK: - 生成标题和图标

        try checkCancellation()
        if shouldAutoRename {
            await updateTitleAndIcon()
        }
    }
}
