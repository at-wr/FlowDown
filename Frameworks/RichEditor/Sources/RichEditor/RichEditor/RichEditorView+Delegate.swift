//
//  RichEditorView+Delegate.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import UIKit

public extension RichEditorView {
    protocol Delegate: AnyObject {
        func onRichEditorSubmit(object: Object, completion: @escaping (Bool) -> Void)
        func onRichEditorError(_ error: String)
        func onRichEditorTogglesUpdate(object: Object)
        func onRichEditorRequestObjectForRestore() -> Object?
        func onRichEditorUpdateObject(object: Object)
        func onRichEditorRequestCurrentModelName() -> String?
        func onRichEditorRequestCurrentModelIdentifier() -> String?
        func onRichEditorPickModel(anchor: UIView, completion: @escaping () -> Void)
        func onRichEditorShowAlternativeModelMenu(anchor: UIView)
        func onRichEditorCheckIfModelSupportsToolCall(_ modelIdentifier: String) -> Bool
        func onRichEditorShowAlternativeToolsMenu(anchor: UIView)
    }
}
