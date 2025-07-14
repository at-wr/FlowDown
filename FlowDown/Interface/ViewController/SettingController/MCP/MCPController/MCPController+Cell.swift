//
//  MCPController+Cell.swift
//  FlowDown
//
//  Created by LiBr on 6/30/25.
//

import ConfigurableKit
import Storage
import UIKit

extension SettingController.SettingContent.MCPController {
    class MCPServerCell: UITableViewCell, UIContextMenuInteractionDelegate {
        private var timer: Timer? = nil

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            let margin = AutoLayoutMarginView(configurableView)
            contentView.addSubview(margin)
            margin.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            separatorInset = .zero
            selectionStyle = .none
            backgroundColor = .clear
            contentView.addInteraction(UIContextMenuInteraction(delegate: self))
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                guard let self else { return }
                guard let clientId else { return }
                configure(with: clientId) // update the status
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        deinit {
            timer?.invalidate()
        }

        let configurableView = ConfigurableActionView(
            responseEverywhere: true,
            actionBlock: { _ in }
        )

        var clientId: ModelContextServer.ID?

        override func prepareForReuse() {
            super.prepareForReuse()
            clientId = nil
        }

        func configure(with clientId: ModelContextServer.ID) {
            self.clientId = clientId
            guard let client = MCPService.shared.server(with: clientId) else {
                return
            }

            let icon = switch client.type {
            case .http:
                UIImage(systemName: "network") ?? UIImage()
            }

            configurableView.configure(icon: icon)

            if !client.name.isEmpty {
                configurableView.configure(title: client.name)
            } else if let url = URL(string: client.endpoint), let host = url.host {
                configurableView.configure(title: "@\(host)")
            } else {
                configurableView.configure(title: "Unknown Server")
            }

            var descriptions: [String] = []
            descriptions.append(client.type.rawValue.uppercased())

            if client.isEnabled {
                let connectionStatusText = getConnectionStatusText(client.connectionStatus)
                descriptions.append(connectionStatusText)

                configurableView.iconView.tintColor = getConnectionStatusColor(client.connectionStatus)
            } else {
                descriptions.append(String(localized: "Disabled"))
                configurableView.iconView.tintColor = .systemGray
            }

            configurableView.configure(description: descriptions.joined(separator: " • "))
        }

        private func getConnectionStatusText(_ status: ModelContextServer.ConnectionStatus) -> String {
            switch status {
            case .connected:
                String(localized: "Connected")
            case .connecting:
                String(localized: "Connecting...")
            case .disconnected:
                String(localized: "Disconnected")
            case .failed:
                String(localized: "Connection Failed")
            }
        }

        private func getConnectionStatusColor(_ status: ModelContextServer.ConnectionStatus) -> UIColor {
            switch status {
            case .connected:
                UIColor(red: 65 / 255.0, green: 190 / 255.0, blue: 171 / 255.0, alpha: 1.0)
            case .connecting:
                .systemOrange
            case .disconnected:
                .systemGray
            case .failed:
                .systemRed
            }
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard let clientId else { return nil }
            let menu = UIMenu(options: [.displayInline], children: [
                UIAction(title: String(localized: "Export Server"), image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    self.exportServer(clientId)
                },
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    MCPService.shared.remove(clientId)
                },
            ])
            #if targetEnvironment(macCatalyst)
                present(menu: menu, anchorPoint: location)
                return nil
            #else
                return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                    menu
                }
            #endif
        }

        private func exportServer(_ serverId: ModelContextServer.ID) {
            guard let server = MCPService.shared.server(with: serverId),
                  let parentViewController
            else { return }

            let tempFileDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("DisposableResources")
                .appendingPathComponent(UUID().uuidString)
            let serverName = URL(string: server.endpoint)?.host ?? "Server"
            let tempFile = tempFileDir
                .appendingPathComponent("Export-\(serverName.sanitizedFileName)")
                .appendingPathExtension("fdmcp")
            try? FileManager.default.createDirectory(at: tempFileDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: tempFile.path, contents: nil)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            try? encoder.encode(server).write(to: tempFile, options: .atomic)

            let exporter = FileExporterHelper()
            exporter.targetFileURL = tempFile
            exporter.referencedView = self
            exporter.deleteAfterComplete = true
            exporter.exportTitle = String(localized: "Export MCP Server")
            exporter.completion = {
                try? FileManager.default.removeItem(at: tempFileDir)
            }
            exporter.execute(presentingViewController: parentViewController)
        }
    }
}
