//
//  Storage+Finders.swift
//  Storage
//
//  Created by Alan Ye on 7/5/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func findConversation(byCloudId cloudId: String) -> Conversation? {
        try? db.getObject(fromTable: Conversation.table, where: Conversation.Properties.cloudId == cloudId)
    }

    func findMessage(byCloudId cloudId: String) -> Message? {
        try? db.getObject(fromTable: Message.table, where: Message.Properties.cloudId == cloudId)
    }

    func findAttachment(byCloudId cloudId: String) -> Attachment? {
        try? db.getObject(fromTable: Attachment.table, where: Attachment.Properties.cloudId == cloudId)
    }

    func findCloudModel(byCloudId cloudId: String) -> CloudModel? {
        cloudModel(with: cloudId)
    }
}
