//
//  MemoryEntry.swift
//  MemoryKit
//
//  Created by Alan Ye on 7/25/25.
//

import Foundation
import Storage
import WCDBSwift

public final class MemoryEntry: Identifiable, Codable, TableCodable {
    // Metadata
    public var id: Int64 = .init()
    public var conversationId: Conversation.ID = .init()
    public var sourceMessageId: Message.ID? = nil
    
    // Memory content
    public var content: String = ""
    public var summary: String = ""
    public var importance: Float = 0.0
    public var memoryType: MemoryType = .factual
    public var tags: [String] = []
    public var metadata: [String: String] = [:]
    
    // Local only
    public var creation: Date = .init()
    public var lastAccessed: Date = .init()
    public var localEmbeddingGenerated: Bool = false
    public var embeddingVersion: String = "v1.0"
    
    // WCDB binding
    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = MemoryEntry
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isAutoIncrement: true, isUnique: true)
            BindColumnConstraint(conversationId, isNotNull: true)
            BindColumnConstraint(sourceMessageId, isNotNull: false, defaultTo: nil)
            BindColumnConstraint(content, isNotNull: true, defaultTo: "")
            BindColumnConstraint(summary, isNotNull: true, defaultTo: "")
            BindColumnConstraint(importance, isNotNull: true, defaultTo: 0.0)
            BindColumnConstraint(memoryType, isNotNull: true, defaultTo: MemoryType.factual.rawValue)
            BindColumnConstraint(tags, isNotNull: true, defaultTo: [String]())
            BindColumnConstraint(metadata, isNotNull: true, defaultTo: [String: String]())
            BindColumnConstraint(creation, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(lastAccessed, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(localEmbeddingGenerated, isNotNull: true, defaultTo: false)
            BindColumnConstraint(embeddingVersion, isNotNull: true, defaultTo: "v1.0")
            
            BindForeginKey(
                conversationId,
                foreignKey: ForeignKey()
                    .references(with: Conversation.table)
                    .columns(Conversation.CodingKeys.id)
                    .onDelete(.cascade)
            )
        }
        
        case id
        case conversationId
        case sourceMessageId
        case content
        case summary
        case importance
        case memoryType
        case tags
        case metadata
        case creation
        case lastAccessed
        case localEmbeddingGenerated
        case embeddingVersion
    }
    
    public var isAutoIncrement: Bool = false
    public var lastInsertedRowID: Int64 = 0
}

// MARK: - MemoryType

extension MemoryType: ColumnCodable {
    public init?(with value: WCDBSwift.Value) {
        self.init(rawValue: value.stringValue)
    }
    
    public func archivedValue() -> WCDBSwift.Value {
        .init(rawValue)
    }
    
    public static var columnType: WCDBSwift.ColumnType {
        .text
    }
}

// MARK: - Array Extensions

extension Array: ColumnCodable where Element == String {
    public init?(with value: WCDBSwift.Value) {
        let data = value.dataValue
        guard let object = try? JSONDecoder().decode([String].self, from: data) else {
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

extension Dictionary: ColumnCodable where Key == String, Value == String {
    public init?(with value: WCDBSwift.Value) {
        let data = value.dataValue
        guard let object = try? JSONDecoder().decode([String: String].self, from: data) else {
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

// MARK: - Hashable & Equatable

extension MemoryEntry: Equatable {
    public static func == (lhs: MemoryEntry, rhs: MemoryEntry) -> Bool {
        lhs.id == rhs.id &&
        lhs.conversationId == rhs.conversationId &&
        lhs.content == rhs.content &&
        lhs.summary == rhs.summary &&
        lhs.importance == rhs.importance &&
        lhs.memoryType == rhs.memoryType
    }
}

extension MemoryEntry: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(conversationId)
        hasher.combine(content)
        hasher.combine(summary)
        hasher.combine(importance)
        hasher.combine(memoryType)
    }
}
