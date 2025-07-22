//
//  ConversationSession+SystemPrompt.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import RichEditor

extension ConversationSession {
    func injectNewSystemCommand(
        _ requestMessages: inout [ChatRequestBody.Message],
        _ modelName: String,
        _ modelWillExecuteTools: Bool,
        _ object: RichEditorView.Object
    ) async {
        let sysPrompt = [
            String(localized:
                """
                System is providing you up to date information about current query:

                Model/Your Name: \(modelName)
                Current Date: \(Date().formatted(date: .long, time: .complete))
                Current User Locale: \(Locale.current.identifier)

                Please use up-to-date information and ensure compliance with the previously provided guidelines.
                """
            ),
        ]
        requestMessages.append(.system(content: .text(sysPrompt.joined(separator: "\n"))))

        if case .bool(true) = object.options[.browsing] {
            let sensitivity = ModelManager.shared.searchSensitivity
            requestMessages.append(
                .system(
                    content: .text(
                        """
                        Web Search Mode: \(sensitivity.title)
                        \(sensitivity.briefDescription)
                        """
                    )
                )
            )
        }

        if modelWillExecuteTools {
            requestMessages.append(
                .system(
                    content: .text(String(localized:
                        """
                        The system provides several tools for your convenience. Please use them wisely and according to the user’s query. Avoid requesting information that is already provided or easily inferred.
                        """
                    ))
                )
            )
        }

        requestMessages.append(.user(content: .text(object.text)))
    }

    func moveSystemMessagesToFront(_ requestMessages: inout [ChatRequestBody.Message]) {
        let systemMessage = requestMessages.reduce(
            (content: "", name: String?.none)
        ) { result, message in
            var newContent = result.content + "\n"
            var newName = result.name
            guard case let .system(content, name) = message else {
                return result
            }
            if let name, result.name == nil {
                newName = name
            }
            switch content {
            case let .parts(parts):
                newContent += parts.joined(separator: "\n")
            case let .text(text):
                newContent += text
            }
            return (newContent, newName)
        }
        if !systemMessage.content.isEmpty {
            requestMessages.removeAll {
                guard case .system = $0 else { return false }
                return true
            }
            let message = ChatRequestBody.Message.system(
                content: .text(systemMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)),
                name: systemMessage.name
            )
            requestMessages.insert(message, at: 0)
        }
    }
}
