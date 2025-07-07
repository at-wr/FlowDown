//
//  ConversationManager.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/31/25.
//

import Combine
import ConfigurableKit
import Foundation
import OrderedCollections
import RichEditor
import Storage
import UIKit

class ConversationManager: NSObject {
    static let shared = ConversationManager()

    @BareCodableStorage(key: "wiki.qaq.conversation.editor.objects", defaultValue: [:])
    private var _temporaryEditorObjects: [Conversation.ID: RichEditorView.Object] {
        didSet { assert(!Thread.isMainThread) }
    }

    var temporaryEditorObjects: [Conversation.ID: RichEditorView.Object] = [:] {
        didSet {
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(saveObjects),
                object: nil
            )
            perform(#selector(saveObjects), with: nil, afterDelay: 1.0)
        }
    }

    let conversations: CurrentValueSubject<[Conversation], Never> = .init([])

    // Track conversation list visibility for optimization
    var isConversationListVisible: Bool = false

    override private init() {
        super.init()
        temporaryEditorObjects = _temporaryEditorObjects
        print("[*] \(temporaryEditorObjects.count) temporary editor objects loaded.")
        scanAll()
    }

    @objc private func saveObjects() {
        DispatchQueue.global().async {
            self._temporaryEditorObjects = self.temporaryEditorObjects
            print("[*] \(self.temporaryEditorObjects.count) temporary editor objects saved.")
        }
    }
}

extension Conversation {
    var interfaceImage: UIImage {
        if let image = UIImage(data: icon) {
            return image
        }
        return "💬"
            .textToImage(size: 64)
            ?? .init(systemName: "quote.bubble")
            ?? .starShine
    }
}
