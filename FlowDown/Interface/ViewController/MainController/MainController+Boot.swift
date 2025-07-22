//
//  MainController+Boot.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/3/25.
//

import AlertController
import Combine
import Foundation
import UIKit

extension MainController {
    func queueBootMessage(text: String) {
        bootMessages.append(text)
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(presentNextBootMessage),
            object: nil
        )
        perform(#selector(presentNextBootMessage), with: nil, afterDelay: 0.5)
    }

    @objc func presentNextBootMessage() {
        let text = bootMessages.joined(separator: "\n")
        bootMessages.removeAll()

        let alert = AlertViewController(
            title: String(localized: "External Resources"),
            message: text
        ) { context in
            context.addAction(title: String(localized: "OK"), attribute: .dangerous) {
                context.dispose {}
            }
        }
        var viewController: UIViewController = self
        while let child = viewController.presentedViewController {
            viewController = child
        }
        viewController.present(alert, animated: true)
    }

    func queueNewConversation(text: String, shouldSend: Bool = false) {
        DispatchQueue.main.async {
            let conversation = ConversationManager.shared.createNewConversation()
            print("[+] created new conversation with ID: \(conversation.id)")
            self.load(conversation.id)
            guard shouldSend else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.chatView.conversationIdentifier == conversation.id {
                    self.sendMessageToCurrentConversation(text)
                }
            }
        }
    }
}
