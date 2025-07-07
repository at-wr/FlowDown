//
//  ModelController+Delegates.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import AlertController
import Foundation
import Storage
import UIKit

extension SettingController.SettingContent.ModelController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        switch itemIdentifier.type {
        case .local:
            let controller = LocalModelEditorController(identifier: itemIdentifier.identifier)
            navigationController?.pushViewController(controller, animated: true)
        case .cloud:
            let controller = CloudModelEditorController(identifier: itemIdentifier.identifier)
            navigationController?.pushViewController(controller, animated: true)
        }
    }

    func tableView(_: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath) else {
            return nil
        }
        let delete = UIContextualAction(
            style: .destructive,
            title: String(localized: "Delete")
        ) { _, _, completion in
            switch itemIdentifier.type {
            case .local:
                ModelManager.shared.removeLocalModel(identifier: itemIdentifier.identifier)
            case .cloud:
                ModelManager.shared.removeCloudModel(identifier: itemIdentifier.identifier)
            }
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath) else {
            return nil
        }
        var actions: [UIMenuElement] = []
        switch itemIdentifier.type {
        case .local: break
        case .cloud:
            actions.append(UIAction(
                title: String(localized: "Duplicate")
            ) { _ in
                switch itemIdentifier.type {
                case .local:
                    preconditionFailure()
                case .cloud:
                    guard let originalModel = ModelManager.shared.cloudModel(identifier: itemIdentifier.identifier) else {
                        return
                    }

                    // for Syncing
                    let duplicatedModel = CloudModel()
                    duplicatedModel.id = UUID().uuidString
                    duplicatedModel.model_identifier = originalModel.model_identifier + " (Copy)"
                    duplicatedModel.model_list_endpoint = originalModel.model_list_endpoint
                    duplicatedModel.creation = Date()
                    duplicatedModel.lastModified = Date()
                    duplicatedModel.endpoint = originalModel.endpoint
                    duplicatedModel.token = originalModel.token
                    duplicatedModel.headers = originalModel.headers
                    duplicatedModel.capabilities = originalModel.capabilities
                    duplicatedModel.context = originalModel.context
                    duplicatedModel.comment = originalModel.comment
                    ModelManager.shared.insertCloudModel(duplicatedModel)
                }
            })
        }
        actions.append(UIAction(
            title: String(localized: "Delete"),
            attributes: .destructive
        ) { _ in
            switch itemIdentifier.type {
            case .local:
                ModelManager.shared.removeLocalModel(identifier: itemIdentifier.identifier)
            case .cloud:
                ModelManager.shared.removeCloudModel(identifier: itemIdentifier.identifier)
            }
        })
        #if targetEnvironment(macCatalyst)
            let cell = tableView.cellForRow(at: indexPath)
            cell?.present(menu: .init(children: actions))
            return nil
        #else
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                .init(children: actions)
            }
        #endif
    }
}

extension SettingController.SettingContent.ModelController: UISearchControllerDelegate, UISearchBarDelegate {
    func searchBar(_: UISearchBar, textDidChange _: String) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(commitSearch), object: nil)
        perform(#selector(commitSearch), with: nil, afterDelay: 0.25)
    }

    @objc func commitSearch() {
        updateDataSource()
    }
}

extension SettingController.SettingContent.ModelController: UIDocumentPickerDelegate {
    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DisposableResources")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
        }
        ModelManager.shared.importModels(at: urls, controller: self)
    }
}

extension SettingController.SettingContent.ModelController: UITableViewDragDelegate {
    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath),
              itemIdentifier.type == .cloud,
              let model = ModelManager.shared.cloudModel(identifier: itemIdentifier.identifier)
        else { return [] }

        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let plistData = try encoder.encode(model)
            let fileName = "Export-\(model.modelDisplayName.sanitizedFileName)\(model.auxiliaryIdentifier).fdmodel"
            let itemProvider = NSItemProvider(item: plistData as NSSecureCoding, typeIdentifier: "wiki.qaq.fdmodel")
            itemProvider.suggestedName = fileName
            let dragItem = UIDragItem(itemProvider: itemProvider)
            dragItem.localObject = model
            return [dragItem]
        } catch {
            print("[-] failed to encode model: \(error)")
            return []
        }
    }
}
