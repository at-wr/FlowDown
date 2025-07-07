//
//  Storage+Message.swift
//  Storage
//
//  Created by 秋星桥 on 1/31/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func makeMessage(with conversationID: Conversation.ID) -> Message {
        let message = Message()
        message.cloudId = UUID().uuidString
        message.conversationId = conversationID
        message.creation = Date()
        message.lastModified = Date()
        message.isAutoIncrement = true
        try? db.insert([message], intoTable: Message.table)
        message.id = message.lastInsertedRowID
        message.isAutoIncrement = false
        return message
    }

    func listMessages() -> [Message] {
        (
            try? db.getObjects(
                fromTable: Message.table,
                orderBy: [
                    Message.Properties.id
                        .order(.ascending),
                ]
            )
        ) ?? []
    }

    func listMessages(within conv: Conversation.ID) -> [Message] {
        (
            try? db.getObjects(
                fromTable: Message.table,
                where: Message.Properties.conversationId == conv,
                orderBy: [
                    Message.Properties.id
                        .order(.ascending),
                ]
            )
        ) ?? []
    }

    func insertOrReplace(object: Message) {
        object.lastModified = Date()
        try? db.insertOrReplace(
            [object],
            intoTable: Message.table
        )
    }

    func insertOrReplace(messages: [Message]) {
        for message in messages {
            message.lastModified = Date()
        }
        try? db.insertOrReplace(messages, intoTable: Message.table)
    }

    func insertOrReplace(identifier: Message.ID, _ block: @escaping (inout Message) -> Void) {
        let read: Message? = try? db.getObject(
            fromTable: Message.table,
            where: Message.Properties.id == identifier
        )
        guard var object = read else { return }
        block(&object)
        object.lastModified = Date()
        try? db.insertOrReplace(
            [object],
            intoTable: Message.table
        )
    }

    func conversationIdentifierLookup(identifier: Message.ID) -> Conversation.ID? {
        let message: Message? = try? db.getObject(
            fromTable: Message.table,
            where: Message.Properties.id == identifier
        )
        guard let identifier = message?.conversationId else {
            assertionFailure()
            return nil
        }
        return identifier
    }

    // rollback forward to delete cell kind WebSearchState and AttachmentHint
    func deleteSupplementMessage(nextTo messageIdentifier: Message.ID) {
        // list all messages in the same conversation
        guard let message: Message = try? db.getObject(
            fromTable: Message.table,
            where: Message.Properties.id == messageIdentifier
        ) else {
            assertionFailure()
            return
        }
        var rollback = messageIdentifier - 1
        while rollback >= 0 {
            defer { rollback -= 1 }
            guard let matcher: Message = try? db.getObject(
                fromTable: Message.table,
                where: Message.Properties.id == rollback
            ) else { continue }
            guard matcher.conversationId == message.conversationId else {
                continue
            }
            guard matcher.role.isSupplementKind else {
                break
            }
            try? db.delete(fromTable: Message.table, where: Message.Properties.id == rollback)
            // continue to delete the previous message if required
        }
    }

    func delete(messageIdentifier: Message.ID) {
        try? db.delete(fromTable: Message.table, where: Message.Properties.id == messageIdentifier)
    }

    func deleteAfter(messageIdentifier: Message.ID) {
        guard let message: Message = try? db.getObject(
            fromTable: Message.table,
            where: Message.Properties.id == messageIdentifier
        ) else {
            assertionFailure()
            return
        }
        try? db.delete(
            fromTable: Message.table,
            where: Message.Properties.id > messageIdentifier &&
                Message.Properties.creation >= message.creation &&
                Message.Properties.conversationId == message.conversationId
        )
    }
}
