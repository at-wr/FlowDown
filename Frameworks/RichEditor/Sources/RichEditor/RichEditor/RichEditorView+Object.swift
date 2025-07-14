//
//  RichEditorView+Object.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import Foundation
import UIKit

public extension RichEditorView {
    struct Object: Codable {
        public var text: String
        public var attachments: [Attachment]
        public var options: [OptionKey: OptionValue]

        public init(text: String = "", attachments: [Attachment] = [], options: [OptionKey: OptionValue] = [:]) {
            self.text = text
            self.attachments = attachments
            self.options = options
        }
    }
}

public extension RichEditorView.Object {
    struct Attachment: Codable, Identifiable, Hashable {
        public let id: UUID
        public let type: AttachmentType
        public var name: String
        public var previewImage: Data
        public var imageRepresentation: Data
        public var textRepresentation: String
        public var storageSuffix: String

        public init(
            id: UUID = .init(),
            type: AttachmentType,
            name: String,
            previewImage: Data,
            imageRepresentation: Data,
            textRepresentation: String,
            storageSuffix: String
        ) {
            self.id = id
            self.type = type
            self.name = name
            self.previewImage = previewImage
            self.imageRepresentation = imageRepresentation
            self.storageSuffix = storageSuffix
            self.textRepresentation = textRepresentation
        }
    }

    enum OptionKey: String, Codable {
        case browsing
        case tools
        case ephemeral
        case storagePrefix
        case modelIdentifier
    }

    enum OptionValue: Codable {
        case string(String)
        case bool(Bool)
        case url(URL)
    }
}

public extension RichEditorView.Object.Attachment {
    enum AttachmentType: String, Codable {
        case image
        case text
    }
}

extension RichEditorView.Object {
    var hasEmptyContent: Bool {
        // text.isEmpty && attachments.isEmpty
        // 要求用户必须发送内容
        text.isEmpty
    }
}

extension RichEditorView {
    func resetValues() {
        inputEditor.set(text: "")
        #if !targetEnvironment(macCatalyst)
            inputEditor.endEditing(true)
        #endif
        attachmentsBar.attachmetns.removeAll()
        controlPanel.close()
        inputEditor.isControlPanelOpened = false
        setNeedsLayout()
        publishNewEditorStatus()
    }

    func submitValues() {
        let object = collectObject()
        guard !object.hasEmptyContent else { return }
        endEditing(true)
        isUserInteractionEnabled = false
        let completion: (Bool) -> Void = { success in
            DispatchQueue.main.async {
                self.isUserInteractionEnabled = true
                if success {
                    self.resetValues()
                    self.storage.removeAll()
                }
            }
        }
        delegate?.onRichEditorSubmit(object: object, completion: completion)
    }

    func publishNewEditorStatus() {
        assert(Thread.isMainThread)
        let object = collectObject()
        guard !objectTransactionInProgress else { return }
        objectTransactionInProgress = true
        defer { objectTransactionInProgress = false }
        delegate?.onRichEditorUpdateObject(object: object)
    }

    func restoreEditorStatusIfPossible() {
        assert(Thread.isMainThread)
        guard let object = delegate?.onRichEditorRequestObjectForRestore() else { return }
        objectTransactionInProgress = true
        defer { objectTransactionInProgress = false }
        resetValues()
        inputEditor.set(text: object.text.trimmingCharacters(in: .whitespacesAndNewlines))
        attachmentsBar.attachmetns.removeAll()
        for attachment in object.attachments {
            attachmentsBar.insert(item: attachment)
        }
        if let browsing = object.options[.browsing], case let .bool(value) = browsing {
            quickSettingBar.browsingToggle.isOn = value
        }
        if let tools = object.options[.tools], case let .bool(value) = tools {
            quickSettingBar.toolsToggle.isOn = value
        }
    }

    public func refill(withText text: String, attachments: [Object.Attachment]) {
        inputEditor.set(text: text)
        attachmentsBar.attachmetns.removeAll()
        for attachment in attachments {
            attachmentsBar.insert(item: attachment)
        }
    }
}
