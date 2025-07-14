import AlertController
import Combine
import ConfigurableKit
import MCP
import Storage
import UIKit

class MCPEditorController: StackScrollController {
    let serverId: ModelContextServer.ID
    var cancellables: Set<AnyCancellable> = .init()

    init(clientId: ModelContextServer.ID) {
        serverId = clientId
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Edit MCP Server")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    let testFooterView = ConfigurableSectionFooterView().with(footer: "")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background

        navigationItem.rightBarButtonItem = .init(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(checkTapped)
        )

        MCPService.shared.servers
            .removeDuplicates()
            .ensureMainThread()
            .delay(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] clients in
                guard let self, isVisible else { return }
                if !clients.contains(where: { $0.id == self.serverId }) {
                    navigationController?.popViewController(animated: true)
                }
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshUI()
    }

    @objc func checkTapped() {
        navigationController?.popViewController(animated: true)
        MCPService.shared.ensureOrReconnect(serverId)
    }

    @objc func exportTapped() {
        guard let server = MCPService.shared.server(with: serverId) else { return }

        let tempFileDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DisposableResources")
            .appendingPathComponent(UUID().uuidString)
        let serverName = if let url = URL(string: server.endpoint), let host = url.host {
            host
        } else if !server.name.isEmpty {
            server.name
        } else {
            "MCPServer"
        }
        let tempFile = tempFileDir
            .appendingPathComponent("Export-\(serverName.sanitizedFileName)")
            .appendingPathExtension("fdmcp")
        try? FileManager.default.createDirectory(at: tempFileDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tempFile.path, contents: nil)

        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(server)
            try data.write(to: tempFile, options: .atomic)

            let exporter = FileExporterHelper()
            exporter.targetFileURL = tempFile
            exporter.referencedView = view
            exporter.deleteAfterComplete = true
            exporter.exportTitle = String(localized: "Export MCP Server")
            exporter.completion = {
                try? FileManager.default.removeItem(at: tempFileDir)
            }
            exporter.execute(presentingViewController: self)
        } catch {
            print("[-] failed to export MCP server: \(error)")
        }
    }

    @objc func deleteTapped() {
        let alert = AlertViewController(
            title: String(localized: "Delete Server"),
            message: String(localized: "Are you sure you want to delete this MCP server? This action cannot be undone.")
        ) { context in
            context.addAction(title: String(localized: "Cancel")) {
                context.dispose()
            }
            context.addAction(title: String(localized: "Delete"), attribute: .dangerous) {
                context.dispose { [weak self] in
                    guard let self else { return }
                    MCPService.shared.remove(serverId)
                    navigationController?.popViewController(animated: true)
                }
            }
        }
        present(alert, animated: true)
    }

    override func setupContentViews() {
        super.setupContentViews()

        guard let server = MCPService.shared.server(with: serverId) else { return }

        if !server.comment.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView()
                    .with(header: String(localized: "Comment"))
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView()
                    .with(footer: server.comment)
            )
        }

        // MARK: - Enabled

        stackView.addArrangedSubview(SeparatorView())
        let enabledView = ConfigurableToggleActionView()
        enabledView.boolValue = server.isEnabled
        enabledView.actionBlock = { value in
            MCPService.shared.edit(identifier: self.serverId) { client in
                client.isEnabled = value
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // let toggle finish animate
                self.refreshUI()
            }
        }
        enabledView.configure(icon: .init(systemName: "power"))
        enabledView.configure(title: String(localized: "Enabled"))
        enabledView.configure(description: String(localized: "Determine if this MCP server is enabled. Tools are only updated when this server is enabled."))
        stackView.addArrangedSubviewWithMargin(enabledView)
        stackView.addArrangedSubview(SeparatorView())

        // MARK: - Connection

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: String(localized: "Connection"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        let typeView = ConfigurableInfoView()
        typeView.configure(icon: .init(systemName: "gear"))
        typeView.configure(title: String(localized: "Connection Type"))
        typeView.configure(description: String(localized: "The transport protocol to use for this client."))
        typeView.configure(value: server.type.rawValue.uppercased())
        typeView.setTapBlock { view in
            let children = [
                UIAction(
                    title: String(localized: "Streamble HTTP"),
                    image: UIImage(systemName: "network")
                ) { _ in
                    MCPService.shared.edit(identifier: self.serverId) { client in
                        client.type = .http
                    }
                    self.refreshUI()
                    view.configure(value: String(localized: "Streamble HTTP"))
                },
            ]
            view.present(
                menu: .init(title: String(localized: "Connection Type"), children: children),
                anchorPoint: .init(x: view.bounds.maxX, y: view.bounds.maxY)
            )
        }
        stackView.addArrangedSubviewWithMargin(typeView)
        stackView.addArrangedSubview(SeparatorView())

        let endpointView = ConfigurableInfoView().setTapBlock { view in
            let placeholder = "https://"

            let input = AlertInputViewController(
                title: String(localized: "Edit Endpoint"),
                message: String(localized: "The URL endpoint for this MCP server. Most of them requires /mcp/ suffix."),
                placeholder: placeholder,
                text: server.endpoint.isEmpty ? "https://" : server.endpoint
            ) { output in
                MCPService.shared.edit(identifier: self.serverId) { client in
                    client.endpoint = output
                }
                self.refreshUI()
                view.configure(value: output.isEmpty ? String(localized: "Not Configured") : output)
            }
            view.parentViewController?.present(input, animated: true)
        }
        endpointView.configure(icon: .init(systemName: "link"))
        endpointView.configure(title: String(localized: "Endpoint"))
        endpointView.configure(description: String(localized: "The URL endpoint for this MCP server. Most of them requires /mcp/ suffix."))
        endpointView.configure(value: server.endpoint.isEmpty ? String(localized: "Not Configured") : server.endpoint)
        stackView.addArrangedSubviewWithMargin(endpointView)
        stackView.addArrangedSubview(SeparatorView())

        let headerView = ConfigurableInfoView().setTapBlock { view in
            guard let client = MCPService.shared.server(with: self.serverId) else { return }
            var text = client.header
            if text.isEmpty { text = "{}" }
            let textEditor = JsonStringMapEditorController(text: text)
            textEditor.title = String(localized: "Edit Headers")
            textEditor.collectEditedContent { result in
                guard let object = try? JSONDecoder().decode([String: String].self, from: result.data(using: .utf8) ?? .init()) else {
                    return
                }
                let jsonData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted)
                let jsonString = String(data: jsonData ?? Data(), encoding: .utf8) ?? ""
                MCPService.shared.edit(identifier: self.serverId) { client in
                    client.header = jsonString == "{}" ? "" : jsonString
                }
                self.refreshUI()
                view.configure(value: object.isEmpty ? String(localized: "No Headers") : String(localized: "Configured"))
            }
            view.parentViewController?.navigationController?.pushViewController(textEditor, animated: true)
        }
        headerView.configure(icon: .init(systemName: "list.bullet"))
        headerView.configure(title: String(localized: "Headers"))
        headerView.configure(description: String(localized: "This value will be added to the request as additional header."))
        headerView.configure(value: server.header.isEmpty ? String(localized: "No Headers") : String(localized: "Configured"))
        stackView.addArrangedSubviewWithMargin(headerView)
        stackView.addArrangedSubview(SeparatorView())

        // MARK: - Test

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: String(localized: "Verification"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let testAction = ConfigurableActionView { [weak self] _ in
            guard let self else { return }
            testConfiguration()
        }
        testAction.configure(icon: UIImage(systemName: "testtube.2"))
        testAction.configure(title: String(localized: "Verify Configuration"))
        testAction.configure(description: String(localized: "Verify the configuration of this MCP server and list available tools for your inform."))
        stackView.addArrangedSubviewWithMargin(testAction)
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(testFooterView) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        // MARK: - Management

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: String(localized: "Management"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let exportOption = ConfigurableActionView { [weak self] _ in
            guard let self else { return }
            exportTapped()
        }
        exportOption.configure(icon: UIImage(systemName: "square.and.arrow.up"))
        exportOption.configure(title: String(localized: "Export Server"))
        exportOption.configure(description: String(localized: "Export this MCP server as a .fdmcp file for sharing or backup."))
        stackView.addArrangedSubviewWithMargin(exportOption)
        stackView.addArrangedSubview(SeparatorView())

        let deleteAction = ConfigurableActionView { [weak self] _ in
            guard let self else { return }
            deleteTapped()
        }
        deleteAction.configure(icon: UIImage(systemName: "trash"))
        deleteAction.configure(title: String(localized: "Delete Server"))
        deleteAction.configure(description: String(localized: "Delete this MCP server permanently."))
        deleteAction.titleLabel.textColor = .systemRed
        deleteAction.iconView.tintColor = .systemRed
        deleteAction.descriptionLabel.textColor = .systemRed
        deleteAction.imageView.tintColor = .systemRed
        stackView.addArrangedSubviewWithMargin(deleteAction)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(UIView())

        // MARK: FOOTER

        let icon = UIImageView().with {
            $0.image = .modelCloud
            $0.tintColor = .separator
            $0.contentMode = .scaleAspectFit
            $0.snp.makeConstraints { make in
                make.width.height.equalTo(24)
            }
        }
        stackView.addArrangedSubviewWithMargin(icon) { $0.bottom /= 2 }

        let footer = UILabel().with {
            $0.font = .rounded(
                ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
                weight: .regular
            )
            $0.textColor = .label.withAlphaComponent(0.25)
            $0.numberOfLines = 0
            $0.text = serverId
            $0.textAlignment = .center
        }
        stackView.addArrangedSubviewWithMargin(footer) { $0.top /= 2 }
        stackView.addArrangedSubviewWithMargin(UIView())
    }
}

extension MCPEditorController {
    func refreshUI() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        setupContentViews()
        applySeparatorConstraints()
    }

    func applySeparatorConstraints() {
        stackView
            .subviews
            .compactMap { view -> SeparatorView? in
                if view is SeparatorView {
                    return view as? SeparatorView
                }
                return nil
            }.forEach {
                $0.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    $0.heightAnchor.constraint(equalToConstant: 1),
                    $0.widthAnchor.constraint(equalTo: stackView.widthAnchor),
                ])
            }
    }

    func testConfiguration() {
        Indicator.progress(
            title: String(localized: "Verifying Configuration"),
            controller: self
        ) { completionHandler in
            MCPService.shared.testConnection(
                serverID: self.serverId
            ) { result in
                completionHandler {
                    switch result {
                    case let .success(tools):
                        Indicator.present(
                            title: String(localized: "Configuration Verified"),
                            haptic: .success,
                            referencingView: self.view
                        )
                        self.testFooterView.with(footer: String(localized: "Available tool(s): \(tools)"))
                    case let .failure(error):
                        let alert = AlertViewController(
                            title: String(localized: "Verification Failed"),
                            message: error.localizedDescription
                        ) { context in
                            context.addAction(title: String(localized: "OK"), attribute: .dangerous) {
                                context.dispose()
                            }
                        }
                        self.present(alert, animated: true)
                        self.testFooterView.with(footer: error.localizedDescription)
                    }
                }
            }
        }
    }
}
