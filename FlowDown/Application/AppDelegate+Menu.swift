//
//  AppDelegate+Menu.swift
//  FlowDown
//
//  Created by Alan Ye on 6/27/25.
//

import AlertController
import OrderedCollections
import Storage
import UIKit

extension AppDelegate {
    // MARK: - Menu Building

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == UIMenuSystem.main else { return }

        builder.insertChild(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: String(localized: "New Chat"),
                        action: #selector(requestNewChatFromMenu(_:)),
                        input: "n",
                        modifierFlags: .command
                    ),
                    UIMenu(
                        title: String(localized: "New Chat with Template"),
                        options: .displayInline,
                        children: Self.buildTemplateMenuItems(target: self)
                    ),
                ]
            ),
            atStartOfMenu: .file
        )
        builder.insertChild(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: String(localized: "Delete Chat"),
                        action: #selector(deleteConversationFromMenu(_:)),
                        input: "\u{8}",
                        modifierFlags: [.command, .shift]
                    ),
                ]
            ),
            atEndOfMenu: .file
        )

        if UpdateManager.shared.canCheckForUpdates {
            builder.insertSibling(
                UIMenu(
                    title: "",
                    options: .displayInline,
                    children: [
                        UIKeyCommand(
                            title: String(localized: "Check for Updates..."),
                            action: #selector(checkForUpdatesFromMenu(_:)),
                            input: "u",
                            modifierFlags: [.command, .shift]
                        ),
                    ]
                ),
                afterMenu: .preferences
            )
        }

        builder.insertSibling(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: String(localized: "Settings..."),
                        action: #selector(openSettingsFromMenu(_:)),
                        input: ",",
                        modifierFlags: .command
                    ),
                ]
            ),
            afterMenu: .preferences
        )

        builder.insertChild(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: String(localized: "Search…"),
                        action: #selector(searchConversationsFromMenu(_:)),
                        input: "f",
                        modifierFlags: [.command, .shift]
                    ),
                ]
            ),
            atStartOfMenu: .edit
        )
        builder.insertChild(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: String(localized: "Previous Conversation"),
                        action: #selector(selectPreviousConversationFromMenu(_:)),
                        input: UIKeyCommand.inputUpArrow,
                        modifierFlags: [.command, .alternate]
                    ),
                    UIKeyCommand(
                        title: String(localized: "Next Conversation"),
                        action: #selector(selectNextConversationFromMenu(_:)),
                        input: UIKeyCommand.inputDownArrow,
                        modifierFlags: [.command, .alternate]
                    ),
                    UIKeyCommand(
                        title: String(localized: "Toggle Sidebar"),
                        action: #selector(toggleSidebarFromMenu(_:)),
                        input: "/",
                        modifierFlags: [.control, .shift]
                    ),
                ].compactMap(\.self)
            ),
            atStartOfMenu: .view
        )
    }

    // MARK: - Template Menu

    private static func buildTemplateMenuItems(target: AppDelegate) -> [UIMenuElement] {
        let templates = Array(ChatTemplateManager.shared.templates.values)
        guard !templates.isEmpty else {
            return [UIAction(title: String(localized: "No Chat Templates"), attributes: .disabled, handler: { _ in })]
        }
        var items: [UIMenuElement] = []
        for (idx, template) in templates.enumerated() {
            let title = "\(template.name)"
            let action = #selector(AppDelegate.requestNewChatWithTemplateFromMenu(_:))
            let propertyList = template.id.uuidString
            if idx < 9 {
                let keyInput = String(idx + 1)
                items.append(
                    UIKeyCommand(
                        title: title,
                        action: action,
                        input: keyInput,
                        modifierFlags: [.command, .alternate],
                        propertyList: propertyList
                    )
                )
            } else {
                items.append(
                    UIAction(
                        title: title,
                        handler: { _ in
                            target.requestNewChatWithTemplateFromMenuWithID(propertyList)
                        }
                    )
                )
            }
        }
        return items
    }

    // MARK: - Menu Actions

    var mainWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first }
            .first
    }

    @objc func checkForUpdatesFromMenu(_: Any?) {
        UpdateManager.shared.anchor(mainWindow?.rootViewController?.view ?? .init())
        UpdateManager.shared.performUpdateCheckFromUI()
    }

    // Wire from MainController
    @objc func requestNewChatFromMenu(_: Any?) {
        (mainWindow?.rootViewController as? MainController)?.requestNewChat()
    }

    @objc func searchConversationsFromMenu(_: Any?) {
        (mainWindow?.rootViewController as? MainController)?.searchConversationsFromMenu()
    }

    @objc func openSettingsFromMenu(_: Any?) {
        (mainWindow?.rootViewController as? MainController)?.openSettings()
    }

    // new chat with template

    @objc func requestNewChatWithTemplateFromMenu(_ sender: UICommand) {
        guard let templateIDString = sender.propertyList as? String,
              let templateID = UUID(uuidString: templateIDString),
              let template = ChatTemplateManager.shared.template(for: templateID)
        else { return }
        let conversationID = ChatTemplateManager.shared.createConversationFromTemplate(template)
        if let mainVC = mainWindow?.rootViewController as? MainController {
            mainVC.sidebar.chatSelection = conversationID
            mainVC.chatView.use(conversation: conversationID) {
                mainVC.chatView.focusEditor()
            }
        }
    }

    func requestNewChatWithTemplateFromMenuWithID(_ templateID: String) {
        guard let id = UUID(uuidString: templateID),
              let template = ChatTemplateManager.shared.template(for: id)
        else { return }
        let conversationID = ChatTemplateManager.shared.createConversationFromTemplate(template)
        if let mainVC = mainWindow?.rootViewController as? MainController {
            mainVC.sidebar.chatSelection = conversationID
            mainVC.chatView.use(conversation: conversationID) {
                mainVC.chatView.focusEditor()
            }
        }
    }

    // conversation related
    private func withCurrentConversation(
        _ block: (MainController, Conversation.ID, Conversation) -> Void
    ) {
        guard let mainVC = mainWindow?.rootViewController as? MainController,
              let conversationID = mainVC.chatView.conversationIdentifier,
              let conversation = ConversationManager.shared.conversation(identifier: conversationID)
        else {
            return
        }
        block(mainVC, conversationID, conversation)
    }

    @objc func deleteConversationFromMenu(_: Any?) {
        withCurrentConversation { _, conversationID, _ in
            ConversationManager.shared.deleteConversation(identifier: conversationID)
        }
    }

    // conversation navigation
    @objc func selectPreviousConversationFromMenu(_: Any?) {
        withCurrentConversation { mainVC, conversationID, _ in
            let list = ConversationManager.shared.conversations.value.values
            guard let currentIndex = list.firstIndex(where: { $0.id == conversationID }), currentIndex > 0 else { return }
            let previousID = list[currentIndex - 1].id
            mainVC.sidebar.chatSelection = previousID
            mainVC.chatView.use(conversation: previousID) {
                mainVC.chatView.focusEditor()
            }
        }
    }

    @objc func selectNextConversationFromMenu(_: Any?) {
        withCurrentConversation { mainVC, conversationID, _ in
            let list = ConversationManager.shared.conversations.value.values
            guard let currentIndex = list.firstIndex(where: { $0.id == conversationID }), currentIndex < list.count - 1 else { return }
            let nextID = list[currentIndex + 1].id
            mainVC.sidebar.chatSelection = nextID
            mainVC.chatView.use(conversation: nextID) {
                mainVC.chatView.focusEditor()
            }
        }
    }

    @objc func toggleSidebarFromMenu(_: Any?) {
        if let mainVC = mainWindow?.rootViewController as? MainController {
            mainVC.view.doWithAnimation { mainVC.isSidebarCollapsed.toggle() }
        }
    }
}
