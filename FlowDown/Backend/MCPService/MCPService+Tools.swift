//
//  MCPService+Tools.swift
//  FlowDown
//
//  Created by Alan Ye on 7/10/25.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import Foundation
import MCP
import UIKit

// MARK: - MCPService Tools Extension

extension MCPService {
    func callTool(name: String, arguments: [String: Value]? = nil, from clientName: String) async throws -> (content: [Tool.Content], isError: Bool?) {
        guard let client = connections[clientName]?.client else {
            throw MCPError.connectionFailed
        }

        return try await client.callTool(name: name, arguments: arguments)
    }

    func getAllTools() async -> [MCPToolInfo] {
        var allTools: [MCPToolInfo] = []

        for (serverID, connection) in connections.compactMapValues(\.client) {
            do {
                guard let server = server(with: serverID), server.isEnabled else {
                    continue
                }
                let name = URL(string: server.endpoint)?.host ?? serverID
                let tools = try await connection.listTools().tools
                let toolInfos = tools.map { MCPToolInfo(tool: $0, serverID: serverID, serverName: name) }
                allTools.append(contentsOf: toolInfos)
            } catch {
                print("[-] failed to acquire tools from \(serverID): \(error.localizedDescription)")
            }
        }

        return allTools
    }
}
