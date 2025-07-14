//
//  MCPController+Bar.swift
//  FlowDown
//
//  Created by LiBr on 6/30/25.
//

import Storage
import UIKit
import UniformTypeIdentifiers

extension SettingController.SettingContent.MCPController {
    @objc func addClientTapped() {
        let menu = UIMenu(children: [
            UIMenu(title: String(localized: "MCP Server"), options: [.displayInline], children: [
                UIMenu(title: String(localized: "MCP Server"), options: [.displayInline], children: [
                    UIAction(title: String(localized: "Create Server"), image: UIImage(systemName: "plus")) { [weak self] _ in
                        let client = MCPService.shared.create()
                        let controller = MCPEditorController(clientId: client.id)
                        self?.navigationController?.pushViewController(controller, animated: true)
                    },
                ]),
                UIMenu(title: String(localized: "Import"), options: [.displayInline], children: [
                    UIAction(title: String(localized: "Import from File"), image: UIImage(systemName: "doc")) { [weak self] _ in
                        self?.presentDocumentPicker()
                    },
                ]),
            ]),
        ])
        guard let bar = navigationController?.navigationBar else { return }
        let point: CGPoint = .init(x: bar.bounds.maxX, y: bar.bounds.midY - 16)
        bar.present(menu: menu, anchorPoint: point)
    }

    func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            UTType(filenameExtension: "fdmcp") ?? .data,
        ])
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }
}
