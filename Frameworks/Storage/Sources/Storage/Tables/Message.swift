//
//  Message.swift
//  Objects
//
//  Created by 秋星桥 on 1/23/25.
//

import Foundation
import MarkdownParser
import WCDBSwift

public final class Message: Identifiable, Codable, TableCodable {
    public var id: Int64 = .init()
    public var cloudId: String = ""
    public var conversationId: Conversation.ID = .init()
    public var creation: Date = .init()
    public var lastModified: Date = .init()
    public var role: Role = .system
    public var thinkingDuration: TimeInterval = 0
    public var reasoningContent: String = ""
    public var isThinkingFold: Bool = false
    public var document: String = ""
    public var documentNodes: [MarkdownBlockNode] = []
    public var webSearchStatus: WebSearchStatus = .init()
    public var toolStatus: ToolStatus = .init()

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = Message
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isAutoIncrement: true, isUnique: true)
            BindColumnConstraint(cloudId, isNotNull: true, isUnique: true, defaultTo: "")
            BindColumnConstraint(conversationId, isNotNull: true)
            BindColumnConstraint(creation, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(lastModified, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(role, isNotNull: true, defaultTo: Role.system.rawValue)
            BindColumnConstraint(thinkingDuration, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(reasoningContent, isNotNull: true, defaultTo: "")
            BindColumnConstraint(isThinkingFold, isNotNull: true, defaultTo: false)
            BindColumnConstraint(document, isNotNull: true, defaultTo: "")
            BindColumnConstraint(documentNodes, isNotNull: true, defaultTo: [MarkdownBlockNode]())
            BindColumnConstraint(webSearchStatus, isNotNull: true, defaultTo: WebSearchStatus())
            BindColumnConstraint(toolStatus, isNotNull: true, defaultTo: ToolStatus())

            BindForeginKey(
                conversationId,
                foreignKey: ForeignKey()
                    .references(with: Conversation.table)
                    .columns(Conversation.CodingKeys.id)
                    .onDelete(.cascade)
            )
        }

        case id
        case cloudId
        case conversationId
        case creation
        case lastModified
        case role
        case thinkingDuration
        case reasoningContent
        case isThinkingFold
        case document
        case documentNodes
        case webSearchStatus
        case toolStatus
    }

    public var isAutoIncrement: Bool = false // 用于定义是否使用自增的方式插入
    public var lastInsertedRowID: Int64 = 0 // 用于获取自增插入后的主键值

    public init() {}
}

public extension Message.Role {
    // role of supplement kind, requires a message to live
    var isSupplementKind: Bool {
        switch self {
        case .userAttachmentHint:
            true
        case .hint:
            true
        case .webSearch:
            true
        case .user:
            false
        case .assistant:
            false
        case .system:
            false
        case .toolHint:
            true
        }
    }
}

public extension Message {
    enum Role: String, Codable, ColumnCodable {
        public init?(with value: WCDBSwift.Value) {
            self.init(rawValue: value.stringValue)
        }

        public func archivedValue() -> WCDBSwift.Value {
            .init(rawValue)
        }

        public static var columnType: WCDBSwift.ColumnType {
            .text
        }

        case user
        /// Attachments are now maintained in a dedicated table.
        /// The use of this role to denote attachments has been discontinued.
        /// This value is considered *deprecated*.
        case userAttachmentHint
        case assistant
        case system
        case hint
        case webSearch
        case toolHint
    }
}

public extension Message {
    struct WebSearchStatus: Codable, ColumnCodable, Hashable {
        public var id: UUID = .init()

        public var queries: [String] = []
        public var currentQuery: Int = 0
        public var currentQueryBeginDate: Date = .init(timeIntervalSince1970: 0)
        public var currentSource: Int = 0
        public var numberOfSource: Int = 0
        public var numberOfWebsites: Int = 0
        public var numberOfResults: Int = 0
        public var proccessProgress: Double = 0

        public struct SearchResult: Codable, Hashable {
            public var title: String
            public var url: URL

            public init(title: String, url: URL) {
                self.title = title
                self.url = url
            }
        }

        public var searchResults: [SearchResult] = []

        public init() {}

        public init?(with value: WCDBSwift.Value) {
            let data = value.dataValue
            guard let object = try? JSONDecoder().decode(
                Message.WebSearchStatus.self,
                from: data
            ) else {
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
    }
}

public extension Message {
    struct ToolStatus: Identifiable, Codable, ColumnCodable, Hashable {
        public var id: UUID = .init()
        public var name: String = .init()
        public var state: Int = 0
        public var message: String = ""

        public init?(with value: WCDBSwift.Value) {
            let data = value.dataValue
            guard let object = try? JSONDecoder().decode(
                Message.ToolStatus.self,
                from: data
            ) else {
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

        public init(name: String = .init(), state: Int = 0, message: String = .init()) {
            self.name = name
            self.state = state
            self.message = message
        }
    }
}

extension Message: Equatable {
    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id &&
            lhs.cloudId == rhs.cloudId &&
            lhs.conversationId == rhs.conversationId &&
            lhs.creation == rhs.creation &&
            lhs.lastModified == rhs.lastModified &&
            lhs.role == rhs.role &&
            lhs.thinkingDuration == rhs.thinkingDuration &&
            lhs.reasoningContent == rhs.reasoningContent &&
            lhs.isThinkingFold == rhs.isThinkingFold &&
            lhs.document == rhs.document &&
            lhs.webSearchStatus == rhs.webSearchStatus
    }
}

extension Message: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(cloudId)
        hasher.combine(conversationId)
        hasher.combine(creation)
        hasher.combine(lastModified)
        hasher.combine(role)
        hasher.combine(thinkingDuration)
        hasher.combine(reasoningContent)
        hasher.combine(isThinkingFold)
        hasher.combine(document)
        hasher.combine(webSearchStatus)
    }
}

extension MarkdownBlockNode: ColumnCodable {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
    public init?(with value: WCDBSwift.Value) {
        let data = value.dataValue
        let object = try? Self.decoder.decode(
            MarkdownBlockNode.self,
            from: data
        )
        if let object {
            self = object
        } else {
            return nil
        }
    }

    public func archivedValue() -> WCDBSwift.Value {
        let data = try? Self.encoder.encode(self)
        return .init(data ?? .init())
    }

    public static var columnType: ColumnType {
        .BLOB
    }
}

extension Message.WebSearchStatus.SearchResult: ColumnCodable {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
    public init?(with value: WCDBSwift.Value) {
        let data = value.dataValue
        let object = try? Self.decoder.decode(
            Message.WebSearchStatus.SearchResult.self,
            from: data
        )
        if let object {
            self = object
        } else {
            return nil
        }
    }

    public func archivedValue() -> WCDBSwift.Value {
        let data = try? Self.encoder.encode(self)
        return .init(data ?? .init())
    }

    public static var columnType: ColumnType {
        .BLOB
    }
}
