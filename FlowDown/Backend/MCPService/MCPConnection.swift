//
//  MCPConnection.swift
//  FlowDown
//
//  Created by Alan Ye on 7/10/25.
//

import Foundation
import MCP
import Storage

// MARK: - Connection Manager

class MCPConnection {
    // MARK: - Properties

    private let config: ModelContextServer
    private(set) var client: MCP.Client?

    // MARK: - Initialization

    init(config: ModelContextServer) {
        self.config = config
    }

    // MARK: - Connection Management

    func connect() async throws {
        guard client == nil else {
            print("[*] client already connected for \(config.id)")
            return
        }

        let client = createClient()
        let transport = try config.createTransport()

        print("[*] connecting client for server: \(config.id)")
        try await client.connect(transport: transport)

        self.client = client
        print("[+] successfully connected to server: \(config.id)")
    }

    func disconnect() {
        guard let client else { return }

        print("[*] disconnecting client for server: \(config.id)")
        Task.detached { await client.disconnect() }
        self.client = nil
        print("[+] client disconnected for server: \(config.id)")
    }

    var isConnected: Bool {
        client != nil
    }

    private func createClient() -> MCP.Client {
        let bundleId = Bundle.main.bundleIdentifier ?? "flowdown.ai"
        return MCP.Client(name: bundleId, version: AnchorVersion.version)
    }
}
