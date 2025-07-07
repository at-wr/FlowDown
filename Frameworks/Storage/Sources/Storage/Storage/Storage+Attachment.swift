//
//  Created by ktiays on 2025/2/24.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import WCDBSwift

public extension Storage {
    func attachment(for messageID: Message.ID) -> [Attachment] {
        (
            try? db.getObjects(
                fromTable: Attachment.table,
                where: Attachment.Properties.messageId == messageID,
                orderBy: [
                    Attachment.Properties.id
                        .order(.ascending),
                ]
            )
        ) ?? []
    }

    func attachmentMake(with messageID: Message.ID) -> Attachment {
        let attachment = Attachment()
        attachment.cloudId = UUID().uuidString // Assign cloudId immediately to prevent sync issues
        attachment.messageId = messageID
        attachment.isAutoIncrement = true
        try? db.insert([attachment], intoTable: Attachment.table)
        attachment.id = attachment.lastInsertedRowID
        attachment.isAutoIncrement = false
        return attachment
    }

    func attachmentsUpdate(_ attachments: [Attachment]) {
        try? db.insertOrReplace(attachments, intoTable: Attachment.table)
    }

    func attachmentRemove(byCloudId cloudId: String) {
        try? db.delete(
            fromTable: Attachment.table,
            where: Attachment.Properties.cloudId == cloudId
        )
    }
}
