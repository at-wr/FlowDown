//
//  RightClickFinder.swift
//  RichEditor
//
//  Created by 秋星桥 on 3/1/25.
//

import UIKit

public class RightClickFinder: NSObject, UIContextMenuInteractionDelegate {
    private lazy var interaction = UIContextMenuInteraction(delegate: self)
    private var action: (() -> Void)? = nil
    private var contextMenuActivationTime: CFTimeInterval = 0

    override public init() {
        super.init()
    }

    public func contextMenuInteraction(
        _: UIContextMenuInteraction,
        configurationForMenuAtLocation _: CGPoint
    ) -> UIContextMenuConfiguration? {
        contextMenuActivationTime = CACurrentMediaTime()
        action?()
        return nil
    }

    public func contextMenuInteraction(
        _: UIContextMenuInteraction,
        willEndFor _: UIContextMenuConfiguration,
        animator _: UIContextMenuInteractionAnimating?
    ) {
        contextMenuActivationTime = 0
    }

    public var isContextMenuActive: Bool {
        let timeSinceActivation = CACurrentMediaTime() - contextMenuActivationTime
        return contextMenuActivationTime > 0 && timeSinceActivation < 0.5
    }

    public func install(on view: UIView, action: @escaping () -> Void) {
        assert(self.action == nil, "RightClickFinder can only be installed once")
        self.action = action
        view.isUserInteractionEnabled = true
        view.addInteraction(interaction)
    }
}
