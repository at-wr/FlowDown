//
//  ConversationSession+Rename.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import Storage

extension ConversationSession {
    func updateTitleAndIcon() async {
        var hasUpdates = false

        if let title = await generateConversationTitle() {
            ConversationManager.shared.editConversation(identifier: id) { conversation in
                conversation.title = title
                conversation.shouldAutoRename = false
            }
            hasUpdates = true
        }

        if let emoji = await generateConversationIcon() {
            ConversationManager.shared.editConversation(identifier: id) { conversation in
                conversation.icon = emoji.textToImage(size: 128)?.pngData() ?? .init()
                conversation.shouldAutoRename = false
            }
            hasUpdates = true
        }

        // Force sync conversation once after all updates to prevent multiple uploads
        if hasUpdates, let conversation = ConversationManager.shared.conversation(identifier: id) {
            CloudKitSyncManager.shared.forceSyncLocalChange(for: conversation, changeType: .update)
        }
    }
}
