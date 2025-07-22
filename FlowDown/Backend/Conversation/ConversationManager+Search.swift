//
//  ConversationManager+Search.swift
//  FlowDown
//
//  Created by Alan Ye on 7/8/25.
//

import Foundation
import Storage

extension ConversationManager {
    func searchConversations(query: String) -> [ConversationSearchResult] {
        guard !query.isEmpty else { return [] }

        let lowercasedQuery = query.lowercased()
        var messageResults: [ConversationSearchResult] = []
        var titleResults: [ConversationSearchResult] = []
        var addedConversations = Set<Conversation.ID>()

        for conversation in conversations.value.values {
            var foundInMessage = false

            let messages = message(within: conversation.id).filter { $0.role != .system }
            for message in messages {
                if message.document.lowercased().contains(lowercasedQuery) {
                    let preview = extractPreview(from: message.document, around: lowercasedQuery)
                    messageResults.append(ConversationSearchResult(
                        conversation: conversation,
                        matchType: .message,
                        matchedText: query,
                        messagePreview: preview
                    ))
                    addedConversations.insert(conversation.id)
                    foundInMessage = true
                    break
                }
            }

            if !foundInMessage, conversation.title.lowercased().contains(lowercasedQuery) {
                titleResults.append(ConversationSearchResult(
                    conversation: conversation,
                    matchType: .title,
                    matchedText: conversation.title
                ))
            }
        }

        return messageResults + titleResults
    }

    private func extractPreview(from text: String, around query: String, maxLength: Int = 100) -> String {
        let lowercasedText = text.lowercased()
        guard let range = lowercasedText.range(of: query.lowercased()) else {
            return String(text.prefix(maxLength))
        }

        let startIndex = text.index(range.lowerBound, offsetBy: -min(30, text.distance(from: text.startIndex, to: range.lowerBound)))
        let endIndex = text.index(range.upperBound, offsetBy: min(70, text.distance(from: range.upperBound, to: text.endIndex)))

        var preview = String(text[startIndex ..< endIndex])
        if startIndex > text.startIndex {
            preview = "..." + preview
        }
        if endIndex < text.endIndex {
            preview = preview + "..."
        }

        return preview.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
