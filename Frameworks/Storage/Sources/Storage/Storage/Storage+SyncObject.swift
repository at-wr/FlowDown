//
//  Storage+SyncObject.swift
//  Storage
//
//  Created by Alan Ye on 7/6/25.
//

import Foundation

/// Notification names for sync integration
public extension NSNotification.Name {
    static let messageDidUpdate = NSNotification.Name("FlowDown.MessageDidUpdate")
    static let conversationDidUpdate = NSNotification.Name("FlowDown.ConversationDidUpdate")
    static let attachmentDidUpdate = NSNotification.Name("FlowDown.AttachmentDidUpdate")
    static let cloudModelDidUpdate = NSNotification.Name("FlowDown.CloudModelDidUpdate")
}

/// Sync-aware operations for Storage
public extension Storage {
    /// Insert or replace a message with sync notification
    func insertOrReplaceMessage(_ message: Message, notifySync: Bool = true) {
        message.lastModified = Date()
        try? db.insertOrReplace([message], intoTable: Message.table)

        if notifySync {
            NotificationCenter.default.post(
                name: .messageDidUpdate,
                object: message,
                userInfo: ["changeType": "update"]
            )
        }
    }

    /// Insert or replace multiple messages with sync notification
    func insertOrReplaceMessages(_ messages: [Message], notifySync: Bool = true) {
        for message in messages {
            message.lastModified = Date()
        }
        try? db.insertOrReplace(messages, intoTable: Message.table)

        if notifySync {
            for message in messages {
                NotificationCenter.default.post(
                    name: .messageDidUpdate,
                    object: message,
                    userInfo: ["changeType": "update"]
                )
            }
        }
    }

    /// Update conversation with sync notification
    func updateConversation(_ conversation: Conversation, notifySync: Bool = true) {
        conversation.lastModified = Date()
        try? db.insertOrReplace([conversation], intoTable: Conversation.table)

        if notifySync {
            NotificationCenter.default.post(
                name: .conversationDidUpdate,
                object: conversation,
                userInfo: ["changeType": "update"]
            )
        }
    }
}
