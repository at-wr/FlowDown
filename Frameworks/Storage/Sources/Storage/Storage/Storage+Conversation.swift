//
//  Storage+Conversation.swift
//  Storage
//
//  Created by 秋星桥 on 1/31/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func conversationList() -> [Conversation] {
        (
            try? db.getObjects(
                fromTable: Conversation.table,
                orderBy: [
                    Conversation.Properties.creation
                        .order(.descending),
                ]
            )
        ) ?? []
    }

    func conversationListAllIdentifiers() -> Set<Conversation.ID> {
        let identifiers = try? db.getColumn(
            on: Conversation.Properties.id,
            fromTable: Conversation.table
        )
        let items = identifiers?.map(\.int64Value) ?? []
        return .init(items)
    }

    func conversationMake() -> Conversation {
        let object = Conversation()
        object.cloudId = UUID().uuidString
        object.isAutoIncrement = true
        try? db.insert([object], intoTable: Conversation.table)
        object.isAutoIncrement = false
        object.id = object.lastInsertedRowID
        return object
    }

    func conversationUpdate(object: Conversation) {
        object.lastModified = Date()
        try? db.insertOrReplace(
            [object],
            intoTable: Conversation.table
        )
    }

    func conversationWith(identifier: Conversation.ID) -> Conversation? {
        try? db.getObject(
            fromTable: Conversation.table,
            where: Conversation.Properties.id == identifier
        )
    }

    func conversationEdit(identifier: Conversation.ID, _ block: @escaping (inout Conversation) -> Void) {
        let read: Conversation? = try? db.getObject(
            fromTable: Conversation.table,
            where: Conversation.Properties.id == identifier
        )
        guard var object = read else { return }
        block(&object)
        object.lastModified = Date()
        try? db.insertOrReplace(
            [object],
            intoTable: Conversation.table
        )
    }

    func conversationRemove(conversationWith identifier: Conversation.ID) {
        let messages = listMessages(within: identifier)
        for message in messages {
            try? db.delete(
                fromTable: Attachment.table,
                where: Attachment.Properties.messageId == message.id
            )
        }
        try? db.delete(
            fromTable: Message.table,
            where: Message.Properties.conversationId == identifier
        )
        try? db.delete(
            fromTable: Conversation.table,
            where: Conversation.Properties.id == identifier
        )
    }

    @discardableResult
    func conversationDuplicate(identifier: Conversation.ID, customize: @escaping (Conversation) -> Void) -> Conversation.ID? {
        var ans: Conversation.ID?
        try? db.run { handler -> Bool in
            do {
                let ret = try self.executeDuplicationTransaction(
                    identifier: identifier,
                    db: handler,
                    customize: customize
                )
                ans = ret
                return true
            } catch {
                assertionFailure(error.localizedDescription)
                return false
            }
        }
        return ans
    }

    private func executeDuplicationTransaction(
        identifier: Conversation.ID,
        db: Handle,
        customize: (Conversation) -> Void
    ) throws -> Conversation.ID {
        let conv: Conversation? = try db.getObject(
            fromTable: Conversation.table,
            where: Conversation.Properties.id == identifier
        )
        guard let conv else { throw NSError() }

        conv.isAutoIncrement = true
        conv.cloudId = UUID().uuidString // cloudId for duplicated conversation
        customize(conv)
        try db.insert([conv], intoTable: Conversation.table)
        conv.isAutoIncrement = false

        let newIdentifier = conv.lastInsertedRowID
        guard newIdentifier != identifier else {
            assertionFailure()
            throw NSError()
        }

        let messages: [Message] = try db.getObjects(
            fromTable: Message.table,
            where: Message.Properties.conversationId == identifier,
            orderBy: [
                Message.Properties.creation.order(.ascending),
            ]
        )

        var oldMessageIdentifierSet = Set<Int64>()
        for message in messages {
            message.isAutoIncrement = true
            message.conversationId = newIdentifier
            message.cloudId = UUID().uuidString // New cloudId for duplicated message
            oldMessageIdentifierSet.insert(message.id)
            try db.insert(message, intoTable: Message.table)
            message.isAutoIncrement = false
            var oldAttachmentIdentifierSet = Set<Int64>()
            let attachments: [Attachment] = try db.getObjects(
                fromTable: Attachment.table,
                where: Attachment.Properties.messageId == message.id
            )
            for attachment in attachments {
                attachment.isAutoIncrement = true
                attachment.messageId = message.lastInsertedRowID
                attachment.cloudId = UUID().uuidString // New cloudId for duplicated attachment
                oldAttachmentIdentifierSet.insert(attachment.id)
                try db.insert(attachment, intoTable: Attachment.table)
                attachment.isAutoIncrement = false
            }
            let newAttachments: [Attachment] = try db.getObjects(
                fromTable: Attachment.table,
                where: Attachment.Properties.messageId == message.lastInsertedRowID
            )
            for attachment in newAttachments {
                guard !oldAttachmentIdentifierSet.contains(attachment.id) else {
                    assertionFailure()
                    throw NSError()
                }
            }
        }

        let newMessages: [Message] = try db.getObjects(
            fromTable: Message.table,
            where: Message.Properties.conversationId == newIdentifier,
            orderBy: [
                Message.Properties.creation.order(.ascending),
            ]
        )
        for message in newMessages {
            guard !oldMessageIdentifierSet.contains(message.id) else {
                assertionFailure()
                throw NSError()
            }
        }

        return newIdentifier
    }

    func conversationsDrop() {
        try? db.run { db -> Bool in
            do {
                try self.executeEraseAllConversations(db: db)
                return true
            } catch {
                assertionFailure(error.localizedDescription)
                return false
            }
        }
    }

    private func executeEraseAllConversations(db: Handle) throws {
        try db.delete(fromTable: Conversation.table)
        try db.delete(fromTable: Message.table)
        try db.delete(fromTable: Attachment.table)
    }
}
