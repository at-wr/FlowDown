//
//  Created by ktiays on 2025/2/12.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ChatClientKit
import Foundation
import Storage

/// The manager for a collection of chat sessions.
final class ConversationSessionManager {
    typealias Session = ConversationSession

    /// Instantiates `ConversationSessionManager` as a singleton.
    static let shared = ConversationSessionManager()

    private var sessions: [Conversation.ID: Session] = [:]

    /// Tracks which conversation is currently active in the UI
    private var activeConversationId: Conversation.ID?

    /// Returns the session for the given conversation ID.
    func session(for id: Conversation.ID) -> Session {
        #if DEBUG
            ConversationSession.allowedInit = id
        #endif

        if let session = sessions[id] { return session }
        let session = Session(id: id)
        if session.messages.isEmpty {
            session.prepareSystemPrompt()
            session.save()
        }
        sessions[id] = session
        return session
    }

    /// Returns true if the session is currently active (displayed in UI or has running tasks)
    func isActive(for id: Conversation.ID) -> Bool {
        if activeConversationId == id {
            return true
        }

        // Check if session has active tasks
        if let session = sessions[id] {
            return session.currentTask != nil || !session.thinkingDurationTimer.isEmpty
        }

        return false
    }

    /// Sets the active conversation (should be called when ChatView switches conversations)
    func setActiveConversation(_ id: Conversation.ID?) {
        activeConversationId = id
    }

    /// Cleans up inactive sessions to save memory
    func cleanupInactiveSessions() {
        let inactiveSessionIds = sessions.keys.filter { id in
            !isActive(for: id)
        }

        for id in inactiveSessionIds {
            sessions.removeValue(forKey: id)
        }

        if !inactiveSessionIds.isEmpty {
            print("[+] cleaned up \(inactiveSessionIds.count) inactive sessions")
        }
    }
}
