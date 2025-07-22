//
//  Sidebar.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/21/25.
//

import Storage
import UIKit

class Sidebar: UIView {
    let brandingLabel = SidebarBrandingLabel()
    let newChatButton = NewChatButton()
    let searchButton = SearchControllerOpenButton()
    let settingButton = SettingButton()
    let conversationListView = ConversationListView()

    var chatSelection: Conversation.ID? {
        didSet {
            guard oldValue != chatSelection else { return }
            if let chatSelection { conversationListView.select(identifier: chatSelection) }
            delegate?.sidebarDidSelectNewChat(chatSelection)
        }
    }

    weak var delegate: Delegate? {
        didSet { delegate?.sidebarDidSelectNewChat(chatSelection) }
    }

    init() {
        super.init(frame: .zero)

        let spacing: CGFloat = 16

        addSubview(brandingLabel)
        addSubview(newChatButton)
        addSubview(settingButton)
        addSubview(searchButton)

        brandingLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.right.equalTo(newChatButton).offset(-spacing)
        }

        newChatButton.delegate = self
        newChatButton.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.width.height.equalTo(32)
            make.centerY.equalTo(brandingLabel.snp.centerY)
        }

        settingButton.snp.makeConstraints { make in
            make.left.bottom.equalToSuperview()
            make.width.height.equalTo(32)
        }
        searchButton.snp.makeConstraints { make in
            make.width.height.equalTo(32)
            make.right.bottom.equalToSuperview()
        }

        searchButton.delegate = self

        conversationListView.delegate = self
        addSubview(conversationListView)
        conversationListView.snp.makeConstraints { make in
            make.top.equalTo(brandingLabel.snp.bottom).offset(spacing)
            make.bottom.equalTo(settingButton.snp.top).offset(-spacing)
            make.left.right.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}

extension Sidebar {
    protocol Delegate: AnyObject {
        func sidebarDidSelectNewChat(_ conv: Conversation.ID?)
        func sidebarRecivedSingleTapForSelection()
    }
}
