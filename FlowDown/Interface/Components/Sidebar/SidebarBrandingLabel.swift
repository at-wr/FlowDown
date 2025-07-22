//
//  SidebarBrandingLabel.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/10/25.
//

import UIKit

class SidebarBrandingLabel: BrandingLabel {
    override init() {
        super.init()
        font = .preferredFont(forTextStyle: .title3).bold
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func updateBrandingLabel() {
        super.updateBrandingLabel()
        #if DEBUG
            text? += " 🐦"
        #endif
    }
}
