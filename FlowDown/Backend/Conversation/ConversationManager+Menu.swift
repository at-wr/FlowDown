//
//  ConversationManager+Menu.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import AlertController
import Foundation
import Storage
import UIKit

private let dateFormatter = DateFormatter().with {
    $0.locale = .current
    $0.dateStyle = .medium
    $0.timeStyle = .short
}

extension ConversationManager {
    func menu(
        forConversation identifier: Conversation.ID?,
        view: UIView,
        suggestNewSelection: @escaping (Conversation.ID) -> Void
    ) -> UIMenu? {
        guard let controller = view.parentViewController else { return nil }
        guard let conv = conversation(identifier: identifier) else { return nil }

        let convHasEmptyContent = ConversationSessionManager.shared.session(for: conv.id)
            .messages
            .filter { [.user, .assistant].contains($0.role) }
            .isEmpty
        let session = ConversationSessionManager.shared.session(for: conv.id)

        let mainMenu = UIMenu(
            title: [
                String(localized: "Conversation"),
                "@",
                dateFormatter.string(from: conv.creation),
            ].joined(separator: " "),
            options: [.displayInline],
            children: [
                UIAction(
                    title: String(localized: "Rename"),
                    image: UIImage(systemName: "pencil.tip.crop.circle.badge.arrow.forward")
                ) { _ in
                    let alert = AlertInputViewController(
                        title: String(localized: "Rename"),
                        message: String(localized: "Set a new title for the conversation. Leave empty to keep unchanged. This will disable auto-renaming."),
                        placeholder: String(localized: "Title"),
                        text: conv.title
                    ) { text in
                        guard !text.isEmpty else { return }
                        ConversationManager.shared.editConversation(identifier: conv.id) {
                            $0.title = text
                            $0.shouldAutoRename = false
                        }
                    }
                    controller.present(alert, animated: true)
                },
                UIAction(
                    title: String(localized: "Pick New Icon"),
                    image: UIImage(systemName: "person.crop.circle.badge.plus")
                ) { _ in
                    let picker = EmojiPickerViewController(sourceView: view) { emoji in
                        ConversationManager.shared.editConversation(identifier: conv.id) {
                            $0.icon = emoji.emoji.textToImage(size: 128)?.pngData() ?? .init()
                            $0.shouldAutoRename = false
                        }
                    }
                    controller.present(picker, animated: true)
                },
            ]
        )

        let savePictureMenu = UIMenu(
            options: [.displayInline],
            children: [
                UIAction(
                    title: String(localized: "Save Image"),
                    image: UIImage(systemName: "text.below.photo")
                ) { _ in
                    let captureView = ConversationCaptureView(session: session)
                    guard let controller = view.parentViewController else { return }
                    Indicator.progress(
                        title: String(localized: "Rednering Content"),
                        controller: controller
                    ) { completionHandler in
                        DispatchQueue.main.async {
                            captureView.capture(controller: controller) { image in
                                completionHandler {
                                    guard let image else {
                                        Indicator.present(
                                            title: String(localized: "Unable to Export"),
                                            preset: .error,
                                            haptic: .error,
                                            referencingView: view
                                        )
                                        return
                                    }

                                    #if targetEnvironment(macCatalyst)
                                        UIPasteboard.general.image = image
                                        Indicator.present(
                                            title: String(localized: "Copied"),
                                            preset: .done,
                                            haptic: .success,
                                            referencingView: view
                                        )
                                    #else
                                        let url = FileManager.default
                                            .temporaryDirectory
                                            .appendingPathComponent("DisposableResources")
                                            .appendingPathComponent("Exported-\(Int(Date().timeIntervalSince1970))".sanitizedFileName)
                                            .appendingPathExtension("png")
                                        try? FileManager.default.createDirectory(
                                            at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true
                                        )
                                        let png = image.pngData()
                                        FileManager.default.createFile(atPath: url.path(), contents: png)

                                        let shareSheet = UIActivityViewController(activityItems: [
                                            url,
                                        ], applicationActivities: [])
                                        shareSheet.popoverPresentationController?.sourceView = view
                                        shareSheet.popoverPresentationController?.sourceRect = view.bounds
                                        shareSheet.completionWithItemsHandler = { _, _, _, _ in
                                            try? FileManager.default.removeItem(at: url)
                                        }
                                        view.parentViewController?.present(shareSheet, animated: true)
                                    #endif
                                }
                            }
                        }
                    }
                },
            ]
        )

        let automationMenu = UIMenu(
            title: String(localized: "Automation"),
            options: [.displayInline],
            children: [
                UIAction(
                    title: String(localized: "Generate New Icon"),
                    image: UIImage(systemName: "arrow.clockwise")
                ) { _ in
                    Indicator.progress(
                        title: String(localized: "Generating New Icon") + "...",
                        controller: controller
                    ) { completion in
                        Task.detached {
                            let sessionManager = ConversationSessionManager.shared
                            let session = sessionManager.session(for: conv.id)
                            if let emoji = await session.generateConversationIcon() {
                                ConversationManager.shared.editConversation(identifier: conv.id) { conversation in
                                    conversation.icon = emoji.textToImage(size: 128)?.pngData() ?? .init()
                                }
                            } else {
                                Indicator.present(
                                    title: String(localized: "Unable to generate icon"),
                                    preset: .error,
                                    haptic: .error,
                                    referencingView: view
                                )
                            }
                            DispatchQueue.main.async {
                                completion {}
                            }
                        }
                    }
                },
                UIAction(
                    title: String(localized: "Generate New Title"),
                    image: UIImage(systemName: "arrow.clockwise")
                ) { _ in
                    Indicator.progress(
                        title: String(localized: "Generating New Title") + "...",
                        controller: controller
                    ) { completion in
                        Task.detached {
                            let sessionManager = ConversationSessionManager.shared
                            let session = sessionManager.session(for: conv.id)
                            if let title = await session.generateConversationTitle() {
                                ConversationManager.shared.editConversation(identifier: conv.id) { conversation in
                                    conversation.title = title
                                }
                            } else {
                                Indicator.present(
                                    title: String(localized: "Unable to generate tittle"),
                                    preset: .error,
                                    haptic: .error,
                                    referencingView: view
                                )
                            }
                            DispatchQueue.main.async {
                                completion {}
                            }
                        }
                    }
                },
            ].compactMap(\.self)
        )

        let managementGroup: [UIMenuElement] = [
            { () -> UIMenuElement? in
                if conv.isFavorite {
                    return UIAction(
                        title: String(localized: "Unfavorite"),
                        image: UIImage(systemName: "star.slash")
                    ) { _ in
                        ConversationManager.shared.editConversation(identifier: conv.id) {
                            $0.isFavorite = false
                        }
                    }
                } else {
                    return nil
                }
            }(),
            { () -> UIMenuElement? in
                if !conv.isFavorite {
                    return UIAction(
                        title: String(localized: "Favorite"),
                        image: UIImage(systemName: "star")
                    ) { _ in
                        ConversationManager.shared.editConversation(identifier: conv.id) {
                            $0.isFavorite = true
                        }
                    }
                } else {
                    return nil
                }
            }(),
            { () -> UIMenu? in
                if !convHasEmptyContent {
                    return savePictureMenu
                } else {
                    return nil
                }
            }(),
            { () -> UIMenu? in
                if convHasEmptyContent {
                    return nil
                } else {
                    return UIMenu(options: [.displayInline], children: [
                        UIAction(
                            title: String(localized: "Compress to New Chat"),
                            image: UIImage(systemName: "arrow.down.doc")
                        ) { _ in
                            let model = session.models.chat
                            let name = ModelManager.shared.modelName(identifier: model)
                            guard let model, !name.isEmpty else {
                                let alert = AlertViewController(
                                    title: String(localized: "Model Not Available"),
                                    message: String(localized: "Please select a model to generate chat template.")
                                ) { context in
                                    context.addAction(title: String(localized: "OK"), attribute: .dangerous) {
                                        context.dispose()
                                    }
                                }
                                controller.present(alert, animated: true)
                                return
                            }
                            let alert = AlertViewController(
                                title: String(localized: "Compress to New Chat"),
                                message: String(localized: "This will use \(name) compress the current conversation into a short summary and create a new chat with it. The original conversation will remain unchanged.")
                            ) { context in
                                context.addAction(title: String(localized: "Cancel")) {
                                    context.dispose()
                                }
                                context.addAction(title: String(localized: "Compress"), attribute: .dangerous) {
                                    context.dispose {
                                        Indicator.progress(
                                            title: String(localized: "Compressing"),
                                            controller: controller
                                        ) { completionHandler in
                                            ConversationManager.shared.compressConversation(
                                                identifier: conv.id,
                                                model: model
                                            ) { convId in
                                                suggestNewSelection(convId)
                                            } completion: { result in
                                                completionHandler {
                                                    switch result {
                                                    case .success:
                                                        Indicator.present(
                                                            title: String(localized: "Conversation Compressed"),
                                                            preset: .done,
                                                            haptic: .success,
                                                            referencingView: view
                                                        )
                                                    case let .failure(failure):
                                                        let alert = AlertViewController(
                                                            title: String(localized: "Failed to Compress Conversation"),
                                                            message: failure.localizedDescription
                                                        ) { context in
                                                            context.addAction(title: String(localized: "OK"), attribute: .dangerous) {
                                                                context.dispose()
                                                            }
                                                        }
                                                        controller.present(alert, animated: true)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            controller.present(alert, animated: true)
                        },
                        UIAction(
                            title: String(localized: "Generate Chat Template"),
                            image: UIImage(systemName: "wind")
                        ) { _ in
                            let model = session.models.chat
                            let name = ModelManager.shared.modelName(identifier: model)
                            guard let model, !name.isEmpty else {
                                let alert = AlertViewController(
                                    title: String(localized: "Model Not Available"),
                                    message: String(localized: "Please select a model to generate chat template.")
                                ) { context in
                                    context.addAction(title: String(localized: "OK"), attribute: .dangerous) {
                                        context.dispose()
                                    }
                                }
                                controller.present(alert, animated: true)
                                return
                            }
                            let alert = AlertViewController(
                                title: String(localized: "Generate Chat Template"),
                                message: String(localized: "This will extract your requests from the current conversation using \(name) and save it as a template for later use. This may take some time.")
                            ) { context in
                                context.addAction(title: String(localized: "Cancel")) {
                                    context.dispose()
                                }
                                context.addAction(title: String(localized: "Generate"), attribute: .dangerous) {
                                    context.dispose {
                                        Indicator.progress(
                                            title: String(localized: "Generating Template"),
                                            controller: controller
                                        ) { completionHandler in
                                            ChatTemplateManager.shared.createTemplateFromConversation(conv, model: model) { result in
                                                completionHandler {
                                                    switch result {
                                                    case let .success(success):
                                                        ChatTemplateManager.shared.addTemplate(success)
                                                        let alert = AlertViewController(
                                                            title: String(localized: "Template Generated"),
                                                            message: String(localized: "Template \(success.name) has been successfully generated and saved.")
                                                        ) { context in
                                                            context.addAction(title: String(localized: "OK")) {
                                                                context.dispose()
                                                            }
                                                            context.addAction(title: String(localized: "Edit"), attribute: .dangerous) {
                                                                context.dispose {
                                                                    let setting = SettingController()
                                                                    SettingController.setNextEntryPage(.chatTemplateEditor(templateIdentifier: success.id))
                                                                    controller.present(setting, animated: true)
                                                                }
                                                            }
                                                        }
                                                        controller.present(alert, animated: true)
                                                    case let .failure(failure):
                                                        let alert = AlertViewController(
                                                            title: String(localized: "Failed to Generate Template"),
                                                            message: failure.localizedDescription
                                                        ) { context in
                                                            context.addAction(title: String(localized: "OK"), attribute: .dangerous) {
                                                                context.dispose()
                                                            }
                                                        }
                                                        controller.present(alert, animated: true)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            controller.present(alert, animated: true)
                        },
                        UIAction(
                            title: String(localized: "Duplicate"),
                            image: UIImage(systemName: "doc.on.doc")
                        ) { _ in
                            if let id = ConversationManager.shared.duplicateConversation(identifier: conv.id) {
                                suggestNewSelection(id)
                            }
                        },
                    ])
                }
            }(),
            { () -> UIMenuElement? in
                if convHasEmptyContent {
                    return UIAction(
                        title: String(localized: "Delete"),
                        image: UIImage(systemName: "trash"),
                        attributes: .destructive
                    ) { _ in
                        ConversationManager.shared.deleteConversation(identifier: conv.id)
                        if let first = ConversationManager.shared.conversations.value.values.first?.id {
                            suggestNewSelection(first)
                        }
                    }
                } else {
                    return UIMenu(
                        title: String(localized: "Delete"),
                        options: [.displayInline],
                        children: [
                            { () -> UIAction? in
                                if !conv.icon.isEmpty {
                                    UIAction(
                                        title: String(localized: "Delete Icon"),
                                        image: UIImage(systemName: "trash"),
                                        attributes: .destructive
                                    ) { _ in
                                        ConversationManager.shared.editConversation(identifier: conv.id) {
                                            $0.icon = .init()
                                        }
                                    }
                                } else { nil }
                            }(),
                            UIAction(
                                title: String(localized: "Delete Conversation"),
                                image: UIImage(systemName: "trash"),
                                attributes: .destructive
                            ) { _ in
                                ConversationManager.shared.deleteConversation(identifier: conv.id)
                                if let first = ConversationManager.shared.conversations.value.values.first?.id {
                                    suggestNewSelection(first)
                                }
                            },
                        ].compactMap(\.self)
                    )
                }
            }(),
        ].compactMap(\.self)

        let management = UIMenu(
            title: String(localized: "Other"),
            image: UIImage(systemName: "ellipsis.circle"),
            options: managementGroup.count <= 1 ? .displayInline : [],
            children: managementGroup
        )

        var finalChildren: [UIMenuElement] = []

        if session.currentTask != nil {
            finalChildren.append(
                UIMenu(options: [.displayInline], children: [
                    UIAction(
                        title: String(localized: "Terminate"),
                        image: UIImage(systemName: "stop.circle"),
                        attributes: [.destructive]
                    ) { _ in
                        session.cancelCurrentTask {}
                    },
                ])
            )
        }

        finalChildren.append(mainMenu)
        if !convHasEmptyContent { finalChildren.append(automationMenu) }
        if !management.children.isEmpty { finalChildren.append(management) }

        return UIMenu(
            title: String(localized: "Edit Conversation"),
            image: UIImage(systemName: "pencil"),
            options: [.displayInline],
            children: finalChildren
        )
    }
}
