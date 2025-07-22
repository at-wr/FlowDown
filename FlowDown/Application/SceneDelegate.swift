//
//  SceneDelegate.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import Combine
import ConfigurableKit
import Storage
import UIKit

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var cancellables = Set<AnyCancellable>()
    lazy var mainController = MainController()

    func scene(
        _ scene: UIScene, willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        #if targetEnvironment(macCatalyst)
            if let titlebar = windowScene.titlebar {
                titlebar.titleVisibility = .hidden
                titlebar.toolbar = nil
            }
        #endif
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 650, height: 650)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = mainController
        self.window = window
        window.makeKeyAndVisible()

        for urlContext in connectionOptions.urlContexts {
            handleIncomingURL(urlContext.url)
        }
    }

    func scene(_: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        for urlContext in contexts {
            handleIncomingURL(urlContext.url)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        switch url.scheme {
        case "file":
            switch url.pathExtension {
            case "fdmodel", "plist":
                importModel(from: url)
            case "fdtemplate":
                importTemplate(from: url)
            case "fdmcp":
                importMCPServer(from: url)
            default: break // dont know how
            }
        case "flowdown":
            handleFlowDownURL(url)
        default:
            break
        }
    }

    private func importModel(from url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        do {
            let model = try ModelManager.shared.importCloudModel(at: url)
            mainController.queueBootMessage(text: String(localized: "Successfully imported model \(model.auxiliaryIdentifier)"))
        } catch {
            mainController.queueBootMessage(text: String(localized: "Failed to import model: \(error.localizedDescription)"))
        }
    }

    private func importTemplate(from url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        do {
            let data = try Data(contentsOf: url)
            let decoder = PropertyListDecoder()
            let template = try decoder.decode(ChatTemplate.self, from: data)
            DispatchQueue.main.async {
                ChatTemplateManager.shared.addTemplate(template)
            }
            mainController.queueBootMessage(text: String(localized: "Successfully imported \(template.name)"))
        } catch {
            print("[*] failed to import template from URL: \(url), error: \(error)")
            mainController.queueBootMessage(text: String(localized: "Failed to import template: \(error.localizedDescription)"))
        }
    }

    private func importMCPServer(from url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        do {
            let data = try Data(contentsOf: url)
            let decoder = PropertyListDecoder()
            let server = try decoder.decode(ModelContextServer.self, from: data)
            DispatchQueue.main.async {
                MCPService.shared.insert(server)
            }
            let serverName = if let serverUrl = URL(string: server.endpoint), let host = serverUrl.host {
                host
            } else if !server.name.isEmpty {
                server.name
            } else {
                "MCP Server"
            }
            mainController.queueBootMessage(text: String(localized: "Successfully imported MCP server \(serverName)"))
        } catch {
            print("[*] failed to import MCP server from URL: \(url), error: \(error)")
            mainController.queueBootMessage(text: String(localized: "Failed to import MCP server: \(error.localizedDescription)"))
        }
    }

    private func handleFlowDownURL(_ url: URL) {
        print("[*] handling incoming message: \(url)")
        guard let host = url.host(), !host.isEmpty else { return }
        switch host {
        case "new": handleNewMessageURL(url)
        default: break
        }
    }

    private func handleNewMessageURL(_ url: URL) {
        let pathComponents = url.pathComponents
        guard pathComponents.count >= 2 else { return }
        let encodedMessage = pathComponents[1]
        let message = encodedMessage.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        mainController.queueNewConversation(text: message, shouldSend: !message.isEmpty)
    }

    func sceneDidDisconnect(_: UIScene) {}

    func sceneDidBecomeActive(_: UIScene) {}

    func sceneWillResignActive(_: UIScene) {}

    func sceneWillEnterForeground(_: UIScene) {}

    func sceneDidEnterBackground(_: UIScene) {}
}
