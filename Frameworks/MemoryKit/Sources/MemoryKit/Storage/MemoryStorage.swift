//
//  MemoryStorage.swift
//  MemoryKit
//
//  Created by Alan Ye on 7/25/25.
//

import Foundation
import Storage
import WCDBSwift

public class MemoryStorage {
    private let db: Database
    
    public init(database: Database) {
        self.db = database
        setupTables()
    }
    
    private func setupTables() {
        do {
            try db.create(table: MemoryEntry.table, of: MemoryEntry.self)
            print("[*] MemoryEntry table created successfully")
        } catch {
            print("[-] Failed to create MemoryEntry table: \(error)")
        }
    }
    
    // MARK: - CRUD
    
    public func insert(memory: MemoryEntry) throws {
        try db.insert(memory, intoTable: MemoryEntry.table)
    }
    
    public func insertOrReplace(memories: [MemoryEntry]) throws {
        try db.insertOrReplace(memories, intoTable: MemoryEntry.table)
    }
    
    public func getMemory(id: Int64) -> MemoryEntry? {
        return try? db.getObject(
            on: MemoryEntry.Properties.all,
            fromTable: MemoryEntry.table,
            where: MemoryEntry.Properties.id == id
        )
    }
    
    public func getMemories(ids: [Int64]) -> [MemoryEntry] {
        guard !ids.isEmpty else { return [] }
        
        do {
            return try db.getObjects(
                on: MemoryEntry.Properties.all,
                fromTable: MemoryEntry.table,
                where: MemoryEntry.Properties.id.in(ids)
            )
        } catch {
            print("[-] Failed to get memories by ids: \(error)")
            return []
        }
    }
    
    public func getMemoriesForConversation(_ conversationId: Conversation.ID, limit: Int = 100) -> [MemoryEntry] {
        do {
            return try db.getObjects(
                on: MemoryEntry.Properties.all,
                fromTable: MemoryEntry.table,
                where: MemoryEntry.Properties.conversationId == conversationId,
                orderBy: [MemoryEntry.Properties.importance.order(.descending),
                         MemoryEntry.Properties.lastAccessed.order(.descending)],
                limit: limit
            )
        } catch {
            print("[-] Failed to get conversation memories: \(error)")
            return []
        }
    }
    
    public func searchMemories(
        query: String,
        conversationId: Conversation.ID? = nil,
        limit: Int = 10
    ) -> [MemoryEntry] {
        do {
            var condition = MemoryEntry.Properties.summary.like("%\(query)%") ||
                           MemoryEntry.Properties.content.like("%\(query)%")
            
            if let conversationId = conversationId {
                condition = condition && MemoryEntry.Properties.conversationId == conversationId
            }
            
            return try db.getObjects(
                on: MemoryEntry.Properties.all,
                fromTable: MemoryEntry.table,
                where: condition,
                orderBy: [MemoryEntry.Properties.importance.order(.descending),
                         MemoryEntry.Properties.lastAccessed.order(.descending)],
                limit: limit
            )
        } catch {
            print("[-] Failed to search memories: \(error)")
            return []
        }
    }
    
    public func updateMemory(_ memory: MemoryEntry) throws {
        memory.lastAccessed = Date()
        try db.insertOrReplace(memory, intoTable: MemoryEntry.table)
    }
    
    public func deleteMemory(id: Int64) throws {
        try db.delete(
            fromTable: MemoryEntry.table,
            where: MemoryEntry.Properties.id == id
        )
    }
    
    public func deleteMemoriesForConversation(_ conversationId: Conversation.ID) throws {
        try db.delete(
            fromTable: MemoryEntry.table,
            where: MemoryEntry.Properties.conversationId == conversationId
        )
    }
    
    // MARK: - Memory Maintenance
    
    public func getMemoryCount() -> Int {
        do {
            return try db.getValue(
                on: MemoryEntry.Properties.id.count(),
                fromTable: MemoryEntry.table
            ) ?? 0
        } catch {
            print("[-] Failed to get memory count: \(error)")
            return 0
        }
    }
    
    public func getMemoriesByImportance(threshold: Float = 0.8, limit: Int = 50) -> [MemoryEntry] {
        do {
            return try db.getObjects(
                on: MemoryEntry.Properties.all,
                fromTable: MemoryEntry.table,
                where: MemoryEntry.Properties.importance >= threshold,
                orderBy: [MemoryEntry.Properties.importance.order(.descending)],
                limit: limit
            )
        } catch {
            print("[-] Failed to get high-importance memories: \(error)")
            return []
        }
    }
    
    public func cleanupOldMemories(olderThan days: Int = 90, minImportance: Float = 0.3) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        try db.delete(
            fromTable: MemoryEntry.table,
            where: MemoryEntry.Properties.lastAccessed < cutoffDate &&
                   MemoryEntry.Properties.importance < minImportance
        )
    }
    
    public func getMemoriesNeedingEmbedding() -> [MemoryEntry] {
        do {
            return try db.getObjects(
                on: MemoryEntry.Properties.all,
                fromTable: MemoryEntry.table,
                where: MemoryEntry.Properties.localEmbeddingGenerated == false,
                orderBy: [MemoryEntry.Properties.importance.order(.descending)],
                limit: 100
            )
        } catch {
            print("[-] Failed to get memories needing embedding: \(error)")
            return []
        }
    }
    
    public func markEmbeddingGenerated(for memoryId: Int64, version: String = "v1.0") throws {
        try db.update(
            table: MemoryEntry.table,
            on: [MemoryEntry.Properties.localEmbeddingGenerated,
                 MemoryEntry.Properties.embeddingVersion],
            with: [true, version],
            where: MemoryEntry.Properties.id == memoryId
        )
    }
}
