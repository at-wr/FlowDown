//
//  QuickSettingBar+Delegate.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/18/25.
//

import Foundation

extension QuickSettingBar {
    protocol Delegate: AnyObject {
        func quickSettingBarOnValueChagned()
        func quickSettingBarPickModel()
        func quickSettingBarShowAlternativeModelMenu()
        func quickSettingBarShowAlternativeToolsMenu()
    }
}
