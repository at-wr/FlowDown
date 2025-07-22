//
//  MCPTool.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/10/25.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import Foundation
import MCP
import Storage

class MCPTool: ModelTool {
    // MARK: - Properties

    public let toolInfo: MCPToolInfo
    public let mcpService: MCPService

    // MARK: - Initialization

    init(toolInfo: MCPToolInfo, mcpService: MCPService) {
        self.toolInfo = toolInfo
        self.mcpService = mcpService
        super.init()
    }

    // MARK: - ModelTool Implementation

    override var shortDescription: String {
        toolInfo.description ?? String(localized: "MCP Tool")
    }

    override var interfaceName: String {
        toolInfo.name
    }

    override var functionName: String {
        toolInfo.name
    }

    override var definition: ChatRequestBody.Tool {
        let parameters = convertMCPSchemaToJSONValues(toolInfo.inputSchema)
        return .function(
            name: toolInfo.name,
            description: toolInfo.description ?? String(localized: "MCP Tool"),
            parameters: parameters,
            strict: false
        )
    }

    override var isEnabled: Bool {
        true
    }

    override class var controlObject: ConfigurableObject {
        assertionFailure()
        return .init(
            icon: "hammer",
            title: String(localized: "MCP Tool"),
            explain: String(localized: "Tools from connected MCP servers"),
            key: "MCP.Tools.Enabled",
            defaultValue: true,
            annotation: .boolean
        )
    }

    // MARK: - Tool Execution

    override func execute(with input: String, anchorTo _: UIView) async throws -> String {
        do {
            var arguments: [String: Value]?
            if !input.isEmpty {
                let data = Data(input.utf8)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    arguments = json.compactMapValues { value in
                        convertJSONValueToMCPValue(value)
                    }
                }
            }

            let result = try await mcpService.callTool(
                name: toolInfo.name,
                arguments: arguments,
                from: toolInfo.serverID
            )

            return formatToolResult(result.content, isError: result.isError)
        } catch {
            throw error
        }
    }

    // MARK: - Private Helper Methods

    private func formatToolResult(_ contents: [Tool.Content], isError: Bool?) -> String {
        var result = ""

        for content in contents {
            switch content {
            case let .text(text):
                result += text
            case let .image(_, mimeType, _):
                result += "[Image: \(mimeType)]"
            case let .resource(uri, text, _):
                result += "[Resource: \(uri)]"
                if !text.isEmpty {
                    result += "\n\(text)"
                }
            case let .audio(_, mimeType):
                result += "[Audio: \(mimeType)]"
            }
            result += "\n"
        }

        if isError == true {
            result = "Error: \(result)"
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension MCPTool {
    private func convertMCPSchemaToJSONValues(_ mcpSchema: Value?) -> [String: JSONValue] {
        guard let mcpSchema else {
            return ["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)]
        }

        if case let .object(dict) = convertMCPValueToJSONValue(mcpSchema) {
            return dict
        }
        return ["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)]
    }

    private func convertMCPValueToJSONValue(_ value: Value) -> JSONValue {
        switch value {
        case let .string(string):
            .string(string)
        case let .int(int):
            .int(int)
        case let .double(double):
            .double(double)
        case let .bool(bool):
            .bool(bool)
        case let .array(values):
            .array(values.map { convertMCPValueToJSONValue($0) })
        case let .object(dict):
            .object(dict.mapValues { convertMCPValueToJSONValue($0) })
        case .null:
            .null(NSNull())
        case let .data(mimeType: mimeType, _):
            .string("[Data: \(mimeType ?? "unknown")]")
        }
    }

    func convertJSONValueToMCPValue(_ jsonValue: Any) -> Value? {
        switch jsonValue {
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if number.isBool {
                return .bool(number.boolValue)
            } else if number.isInteger {
                return .int(number.intValue)
            } else {
                return .double(number.doubleValue)
            }
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let array as [Any]:
            let values = array.compactMap { convertJSONValueToMCPValue($0) }
            return .array(values)
        case let dict as [String: Any]:
            let pairs = dict.compactMapValues { convertJSONValueToMCPValue($0) }
            return .object(pairs)
        case is NSNull:
            return .null
        default:
            return nil
        }
    }
}
