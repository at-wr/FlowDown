//
//  ModelController+Bar.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import AlertController
import ChidoriMenu
import ConfigurableKit
import MLX
import Storage
import UIKit
import UniformTypeIdentifiers

extension SettingController.SettingContent.ModelController {
    private func createCloudModelMenuItems() -> [UIMenuElement] {
        [
            UIMenu(
                title: String(localized: "pollinations.ai (free)"),
                image: .init(systemName: "network"),
                children: CloudModel.BuiltinModel.allCases.map(\.model).map { model in
                    UIAction(
                        title: model.model_identifier,
                        image: .init(systemName: "network")
                    ) { [weak self] _ in
                        _ = ModelManager.shared.newCloudModel(profile: model)
                        Indicator.present(
                            title: String(localized: "Model Added"),
                            preset: .done,
                            haptic: .success,
                            referencingView: self?.view
                        )
                    }
                }
            ),
            UIAction(
                title: String(localized: "Empty Model"),
                image: .init(systemName: "square.dashed")
            ) { [weak self] _ in
                guard let self else { return }
                let profile = CloudModel()
                _ = ModelManager.shared.newCloudModel(profile: profile)
                let controller = CloudModelEditorController(identifier: profile.id)
                navigationController?.pushViewController(controller, animated: true)
            },
        ]
    }

    private func createLocalModelMenuItems() -> [UIMenuElement] {
        [
            UIAction(
                title: String(localized: "Download @ Hugging Face"),
                image: .init(systemName: "icloud.and.arrow.down")
            ) { [weak self] _ in
                guard MLX.GPU.isSupported else {
                    let alert = AlertViewController(
                        title: String(localized: "Unsupporte"),
                        message: String(localized: "Your device does not support MLX.")
                    ) { context in
                        context.addAction(title: String(localized: "OK"), attribute: .dangerous) {
                            context.dispose()
                        }
                    }
                    self?.present(alert, animated: true)
                    return
                }
                guard let nav = self?.navigationController else { return }
                nav.pushViewController(HubModelDownloadController(), animated: true)
            },
            UIAction(
                title: String(localized: "Connect @ OLLAMA"),
                image: .init(systemName: "cable.connector.horizontal")
            ) { [weak self] _ in
                let profile = CloudModel()
                _ = ModelManager.shared.newCloudModel(profile: profile)
                let controller = CloudModelEditorController(identifier: profile.id)
                self?.navigationController?.pushViewController(controller, animated: true)
            },
            UIAction(
                title: String(localized: "Connect @ LM Studio"),
                image: .init(systemName: "cable.connector.horizontal")
            ) { [weak self] _ in
                let profile = CloudModel()
                _ = ModelManager.shared.newCloudModel(profile: profile)
                let controller = CloudModelEditorController(identifier: profile.id)
                self?.navigationController?.pushViewController(controller, animated: true)
            },
        ]
    }

    @objc func addModelBarItemTapped() {
        guard let bar = navigationController?.navigationBar else { return }

        let menu = UIMenu(
            title: String(localized: "Select Model Type"),
            options: [.displayInline],
            children: [
                UIMenu(
                    title: String(localized: "Cloud Model"),
                    options: [.displayInline],
                    children: createCloudModelMenuItems()
                ),
                UIMenu(
                    title: String(localized: "Local Model"),
                    options: [.displayInline],
                    children: createLocalModelMenuItems()
                ),
                UIMenu(
                    title: String(localized: "Import Model"),
                    options: [.displayInline],
                    children: [
                        UIAction(
                            title: String(localized: "Import from File"),
                            image: .init(systemName: "arrow.down.doc")
                        ) { [weak self] _ in
                            guard let self else { return }
                            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
                                .zip, .propertyList, UTType(filenameExtension: "fdmodel") ?? .data,
                            ], asCopy: true)
                            picker.title = String(localized: "Import Model")
                            picker.delegate = self
                            picker.allowsMultipleSelection = true
                            picker.modalPresentationStyle = .formSheet
                            present(picker, animated: true)
                        },
                    ]
                ),
            ]
        )
        let point: CGPoint = .init(x: bar.bounds.maxX, y: bar.bounds.midY - 16)
        bar.present(menu: menu, anchorPoint: point)
    }

    @objc func filterBarItemTapped() {
        guard let bar = navigationController?.navigationBar else { return }
        let menu = UIMenu(title: String(localized: "Filter Options"), children: [
            UIAction(
                title: String(localized: "Show Local Models"),
                image: .modelLocal,
                state: showLocalModels ? .on : .off
            ) { [weak self] _ in
                self?.showLocalModels.toggle()
            },
            UIAction(
                title: String(localized: "Show Cloud Models"),
                image: .modelCloud,
                state: showCloudModels ? .on : .off
            ) { [weak self] _ in
                self?.showCloudModels.toggle()
            },
        ])
        let point: CGPoint = .init(x: bar.bounds.maxX, y: bar.bounds.midY - 16)
        bar.present(menu: menu, anchorPoint: point)
    }
}
