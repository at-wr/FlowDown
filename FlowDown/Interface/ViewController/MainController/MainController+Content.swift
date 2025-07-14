//
//  MainController+Content.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/20/25.
//

import Foundation
import Storage
import UIKit

extension MainController {
    func setupViews() {
        textureBackground.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        sidebarLayoutView.clipsToBounds = true
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous

        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .background
        contentShadowView.layer.cornerRadius = contentView.layer.cornerRadius
        contentShadowView.layer.cornerCurve = contentView.layer.cornerCurve

        contentShadowView.snp.makeConstraints { make in
            make.edges.equalTo(contentView)
        }

        sidebarDragger.snp.makeConstraints { make in
            make.right.equalTo(contentView.snp.left)
            make.top.bottom.equalToSuperview()
            make.width.equalTo(10)
        }

        contentView.hideKeyboardWhenTappedAround()

        chatView.onCreateNewChat = { [weak self] in
            self?.requestNewChat()
        }
        chatView.onSuggestNewChat = { [weak self] id in
            guard let self else { return }
            load(id)
        }
        chatView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        sidebar.delegate = self
        sidebar.newChatButton.delegate = self
        sidebar.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        sidebar.conversationListView.tableView.gestureRecognizers?.forEach {
            guard $0 is UIPanGestureRecognizer else { return }
            $0.cancelsTouchesInView = false
        }

        #if !targetEnvironment(macCatalyst)
            chatView.escapeButton.actionBlock = { [weak self] in
                self?.view.doWithAnimation {
                    self?.isSidebarCollapsed.toggle()
                }
            }
        #endif
    }

    func load(_ conv: Conversation.ID?) {
        print("[MainController] sidebarDidSelectNewChat: \(conv ?? -1)")
        chatView.prepareForReuse()
        guard let identifier = conv else { return }

        sidebar.chatSelection = identifier
        chatView.use(conversation: identifier)

        let session = ConversationSessionManager.shared.session(for: identifier)
        session.updateModels()
    }
}

extension MainController: Sidebar.Delegate {
    func sidebarRecivedSingleTapForSelection() {
        #if !targetEnvironment(macCatalyst)
            DispatchQueue.main.async {
                guard self.presentedViewController == nil else { return }
                guard !self.allowSidebarPersistence else { return }
                let tableView = self.sidebar.conversationListView.tableView
                guard !tableView.isEditing else { return }
                self.view.doWithAnimation { self.isSidebarCollapsed = true }
            }
        #endif
    }

    func sidebarDidSelectNewChat(_ conv: Conversation.ID?) {
        load(conv)
    }
}
