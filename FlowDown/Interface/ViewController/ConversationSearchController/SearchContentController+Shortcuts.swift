//
//  SearchContentController+Shortcuts.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/9/25.
//

extension SearchContentController: KeyboardNavigationDelegate {
    func didPressUpArrow() {
        handleUpArrow()
    }

    func didPressDownArrow() {
        handleDownArrow()
    }

    func didPressEnter() {
        handleEnterKey()
    }
}
