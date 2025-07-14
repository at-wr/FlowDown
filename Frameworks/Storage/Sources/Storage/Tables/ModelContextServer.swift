//
//  ModelContextServer.swift
//  Storage
//
//  Created by LiBr on 6/29/25.
//
import Foundation
import WCDBSwift

public struct StringArrayCodable: ColumnCodable {
    public let array: [String]

    public init(_ array: [String]) {
        self.array = array
    }

    public init?(with value: WCDBSwift.Value) {
        let data = value.stringValue.data(using: .utf8) ?? Data()
        guard let array = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        self.array = array
    }

    public func archivedValue() -> WCDBSwift.Value {
        let data = (try? JSONEncoder().encode(array)) ?? Data()
        return .init(String(data: data, encoding: .utf8) ?? "[]")
    }

    public static var columnType: WCDBSwift.ColumnType {
        .text
    }
}

public final class ModelContextServer: Identifiable, Codable, TableCodable {
    public var id: String = UUID().uuidString
    public var name: String = ""
    public var comment: String = ""
    public var type: ServerType = .http
    public var endpoint: String = ""
    public var header: String = ""
    public var timeout: Int = 60
    public var isEnabled: Bool = true
    public var toolsEnabled: EnableCodable = .init()
    public var resourcesEnabled: EnableCodable = .init()
    public var templateEnabled: EnableCodable = .init()
    public var lastConnected: Date?
    public var connectionStatus: ConnectionStatus = .disconnected
    public var capabilities: StringArrayCodable = .init([])

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = ModelContextServer
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, defaultTo: UUID().uuidString)
            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(comment, isNotNull: true, defaultTo: "")
            BindColumnConstraint(type, isNotNull: true, defaultTo: ServerType.http.rawValue)
            BindColumnConstraint(endpoint, isNotNull: true, defaultTo: "")
            BindColumnConstraint(header, isNotNull: true, defaultTo: "")
            BindColumnConstraint(timeout, isNotNull: true, defaultTo: 60)
            BindColumnConstraint(isEnabled, isNotNull: true, defaultTo: true)
            BindColumnConstraint(toolsEnabled, isNotNull: true, defaultTo: EnableCodable())
            BindColumnConstraint(resourcesEnabled, isNotNull: true, defaultTo: EnableCodable())
            BindColumnConstraint(templateEnabled, isNotNull: true, defaultTo: EnableCodable())
            BindColumnConstraint(lastConnected, isNotNull: false)
            BindColumnConstraint(connectionStatus, isNotNull: true, defaultTo: ConnectionStatus.disconnected.rawValue)
            BindColumnConstraint(capabilities, isNotNull: true, defaultTo: StringArrayCodable([]))
        }

        case id
        case name
        case comment
        case type
        case endpoint
        case header
        case timeout
        case isEnabled
        case toolsEnabled
        case templateEnabled
        case resourcesEnabled
        case lastConnected
        case connectionStatus
        case capabilities
    }

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        comment: String = "",
        type: ServerType = .http,
        endpoint: String = "",
        header: String = "",
        timeout: Int = 60,
        isEnabled: Bool = true,
        toolsEnabled: EnableCodable = .init(),
        resourcesEnabled: EnableCodable = .init(),
        templateEnabled: EnableCodable = .init(),
        lastConnected: Date? = nil,
        connectionStatus: ConnectionStatus = .disconnected,
        capabilities: StringArrayCodable = StringArrayCodable([])
    ) {
        self.id = id
        self.name = name
        self.comment = comment
        self.type = type
        self.endpoint = endpoint
        self.header = header
        self.timeout = timeout
        self.isEnabled = isEnabled
        self.toolsEnabled = toolsEnabled
        self.resourcesEnabled = resourcesEnabled
        self.templateEnabled = templateEnabled
        self.lastConnected = lastConnected
        self.connectionStatus = connectionStatus
        self.capabilities = capabilities
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ModelContextServer: Equatable {
    public static func == (lhs: ModelContextServer, rhs: ModelContextServer) -> Bool {
        lhs.id == rhs.id
    }
}

extension ModelContextServer: Hashable {}

public extension ModelContextServer {
    enum ServerType: String, Codable, ColumnCodable {
        case http

        public init?(with value: WCDBSwift.Value) {
            let rawValue = value.stringValue
            self.init(rawValue: rawValue)
        }

        public func archivedValue() -> WCDBSwift.Value {
            .init(rawValue)
        }

        public static var columnType: WCDBSwift.ColumnType {
            .text
        }
    }

    enum ConnectionStatus: String, Codable, ColumnCodable {
        case disconnected
        case connecting
        case connected
        case failed

        public init?(with value: WCDBSwift.Value) {
            let rawValue = value.stringValue
            self.init(rawValue: rawValue)
        }

        public func archivedValue() -> WCDBSwift.Value {
            .init(rawValue)
        }

        public static var columnType: WCDBSwift.ColumnType {
            .text
        }
    }
}

public extension ModelContextServer {
    struct EnableCodable: Codable, ColumnCodable {
        public init?(with value: WCDBSwift.Value) {
            let data = value.dataValue
            guard let object = try? JSONDecoder().decode(EnableCodable.self, from: data) else {
                return nil
            }
            self = object
        }

        public func archivedValue() -> WCDBSwift.Value {
            let data = try! JSONEncoder().encode(self)
            return .init(data)
        }

        public static var columnType: WCDBSwift.ColumnType {
            .BLOB
        }

        public var value: [String: Bool] = [:]

        public init() {
            value = [:]
        }

        public init(value: [String: Bool]) {
            self.value = value
        }
    }
}
