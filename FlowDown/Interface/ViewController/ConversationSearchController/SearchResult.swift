//
//  SearchResult.swift
//  Storage
//
//  Created by Alan Ye on 7/8/25.
//

import Foundation
import Storage

struct ConversationSearchResult {
    let conversation: Conversation
    let matchType: MatchType
    let matchedText: String
    let messagePreview: String?

    enum MatchType {
        case title
        case message
    }

    init(
        conversation: Conversation,
        matchType: MatchType,
        matchedText: String,
        messagePreview: String? = nil
    ) {
        self.conversation = conversation
        self.matchType = matchType
        self.matchedText = matchedText
        self.messagePreview = messagePreview
    }
}
