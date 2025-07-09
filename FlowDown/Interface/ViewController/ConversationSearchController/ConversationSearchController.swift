//
//  ConversationSearchController.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//  Implemented by Alan Ye on 7/8/25 with Love :)
//

import AlertController
import SnapKit
import Storage
import UIKit

#if targetEnvironment(macCatalyst)
    class ConversationSearchController: AlertBaseController {
        init(callback: @escaping SearchCallback) {
            super.init(
                rootViewController: NavigationController(callback: callback),
                preferredWidth: 660,
                preferredHeight: 420
            )
            shouldDismissWhenTappedAround = true
            shouldDismissWhenEscapeKeyPressed = true
        }

        override func contentViewDidLoad() {
            super.contentViewDidLoad()
            contentView.backgroundColor = .background
        }

        class NavigationController: UINavigationController {
            init(callback: @escaping SearchCallback) {
                super.init(rootViewController: SearchContentController(callback: callback))
                navigationBar.isHidden = true
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError()
            }
        }
    }
#else
    class ConversationSearchController: UINavigationController {
        init(callback: @escaping SearchCallback) {
            super.init(rootViewController: SearchContentController(callback: callback))
            navigationBar.isHidden = true
            modalPresentationStyle = .formSheet
            modalTransitionStyle = .coverVertical
            preferredContentSize = .init(width: 550, height: 550)
            view.backgroundColor = .background
            isModalInPresentation = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }
    }
#endif

extension ConversationSearchController {
    typealias SearchCallback = (Conversation.ID?) -> Void
}
