//
//  KeyboardNavigationSearchBar.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/9/25.
//

import UIKit

class KeyboardNavigationSearchBar: UISearchBar {
    weak var keyboardNavigationDelegate: KeyboardNavigationDelegate?

    override func awakeFromNib() {
        super.awakeFromNib()
        setupKeyboardHandling()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupKeyboardHandling()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeyboardHandling()
    }

    private func setupKeyboardHandling() {}

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }

            switch key.keyCode {
            case .keyboardReturnOrEnter:
                keyboardNavigationDelegate?.didPressEnter()
                return
            case .keyboardUpArrow:
                keyboardNavigationDelegate?.didPressUpArrow()
                return
            case .keyboardDownArrow:
                keyboardNavigationDelegate?.didPressDownArrow()
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }
}
