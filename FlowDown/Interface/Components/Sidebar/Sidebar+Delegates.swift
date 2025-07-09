//
//  Sidebar+Delegates.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import Foundation
import Storage
import UIKit

extension Sidebar: NewChatButton.Delegate {
    func newChatDidCreated(_ identifier: Conversation.ID) {
        chatSelection = identifier
    }
}

extension Sidebar: ConversationListView.Delegate {
    func conversationListView(didSelect identifier: Conversation.ID?) {
        chatSelection = identifier
    }
}

extension Sidebar: SearchControllerOpenButton.Delegate {
    func searchButtonDidTap() {
        let controller = ConversationSearchController { [weak self] conversationId in
            if let conversationId {
                self?.chatSelection = conversationId
                // Collapse sidebar after search dismissal only on compact size classes
                if let mainController = self?.parentViewController as? MainController,
                   mainController.traitCollection.horizontalSizeClass == .compact
                {
                    mainController.view.doWithAnimation {
                        mainController.isSidebarCollapsed = true
                    }
                }
            }
        }
        parentViewController?.present(controller, animated: true)
    }
}
