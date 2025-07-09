//
//  SearchResult.swift
//  Storage
//
//  Created by Alan Ye on 7/8/25.
//

import Foundation

public struct SearchResult {
    public let conversation: Conversation
    public let matchType: MatchType
    public let matchedText: String
    public let messagePreview: String?

    public enum MatchType {
        case title
        case message
    }

    public init(
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
