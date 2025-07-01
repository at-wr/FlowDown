//
//  ConversationManager+CRUD.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/31/25.
//

import Combine
import Foundation
import RichEditor
import Storage

extension ConversationManager {
    func scanAll() {
        let items = sdb.listConversations()
        print("[+] scanned \(items.count) conversations")
        conversations.send(items)
    }

    func initialConversation() -> Conversation {
        if let firstItem = conversations.value.first,
           message(within: firstItem.id).isEmpty
        {
            print("[+] using first empty conversation with index: \(firstItem.id)")
            return firstItem
        }
        print("[+] creating a new conversation")
        return createNewConversation()
    }

    func createNewConversation() -> Conversation {
        let tempObject = sdb.createNewConversation()
        sdb.insertOrReplace(identifier: tempObject.id) { conv in
            conv.title = String(localized: "Conversation")
            if conv.modelId?.isEmpty ?? true {
                conv.modelId = ModelManager.ModelIdentifier.defaultModelForConversation
            }
        }
        scanAll()
        guard let object = sdb.conversation(identifier: tempObject.id) else {
            preconditionFailure()
        }
        print("[+] created a new conversation with id: \(object.id)")
        NotificationCenter.default.post(name: .newChatCreated, object: object.id)
        // guide message when no history message
        if ConversationManager.shouldShowGuideMessage {
            if conversations.value.count <= 1 {
                let session = ConversationSessionManager.shared.session(for: object.id)
                let guide = String(localized:
                    """
                    **Welcome to FlowDown🐦**, a blazing fast and smooth client app for LLMs with respect of your privacy.

                    Free models included. You can also _configure cloud models_ or _run local models_ on device.

                    💡 For more information, check out [our wiki](https://apps.qaq.wiki/docs/flowdown/).

                    ---
                    **What to do next?**

                    1. Select or _add a new model_, and **create a new conversation**.
                    2. Later, you can go to **Settings** to customize your experience.
                    3. For any issues, feel free to [contact us](https://discord.gg/UHKMRyJcgc).

                    ✨ **Enjoy your FlowDown experience!**
                    """
                )

                let message = session.appendNewMessage(role: .assistant)
                message.document = guide
                session.save()
                sdb.insertOrReplace(object: message)
                session.notifyMessagesDidChange()

                editConversation(identifier: object.id) { conversation in
                    conversation.title = String(localized: "Introduction to FlowDown")
                    conversation.icon = "🥳".textToImage(size: 128)?.pngData() ?? .init()
                    conversation.shouldAutoRename = false
                }

                ConversationManager.shouldShowGuideMessage = false
            }
        }
        return object
    }

    func conversation(identifier: Conversation.ID?) -> Conversation? {
        if let identifier {
            sdb.conversation(identifier: identifier)
        } else {
            nil
        }
    }

    func editConversation(identifier: Conversation.ID, block: @escaping (inout Conversation) -> Void) {
        let conv = conversation(identifier: identifier)
        guard var conv else { return }
        block(&conv)
        sdb.insertOrReplace(object: conv)
        scanAll()
    }

    func duplicateConversation(identifier: Conversation.ID) -> Conversation.ID? {
        let ans = sdb.duplicate(identifier: identifier) { conv in
            conv.creation = .init()
            conv.title = String(
                format: String(localized: "%@ Copy"),
                conv.title
            )
        }
        scanAll()
        return ans
    }

    func deleteConversation(identifier: Conversation.ID) {
        let session = ConversationSessionManager.shared.session(for: identifier)
        session.cancelCurrentTask {}
        sdb.remove(identifier: identifier)
        setRichEditorObject(identifier: identifier, nil)
        scanAll()
    }

    func eraseAll() {
        sdb.eraseAllConversations()
        clearRichEditorObject()
        ConversationManager.shouldShowGuideMessage = true
        scanAll()
    }

    func conversationIdentifierLookup(from messageIdentifier: Message.ID) -> Conversation.ID? {
        sdb.conversationIdentifierLookup(identifier: messageIdentifier)
    }
}

extension ConversationManager {
    func message(within conv: Conversation.ID) -> [Message] {
        sdb.listMessages(within: conv)
    }
}

extension Notification.Name {
    static let newChatCreated = Notification.Name("newChatCreated")
}

extension ConversationManager {
    static var shouldShowGuideMessage: Bool {
        get {
            if UserDefaults.standard.object(forKey: "ShowGuideMessage") == nil {
                // true on initial start
                UserDefaults.standard.set(true, forKey: "ShowGuideMessage")
                return true
            }
            return UserDefaults.standard.bool(forKey: "ShowGuideMessage")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ShowGuideMessage")
        }
    }
}
