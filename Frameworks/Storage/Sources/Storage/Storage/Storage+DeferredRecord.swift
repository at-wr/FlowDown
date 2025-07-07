//
//  Storage+DeferredRecord.swift
//  Storage
//
//  Created by Alan Ye on 7/5/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    /// Adds a deferred record to the queue
    func deferredRecordEnqueue(_ record: DeferredRecord) {
        try? db.insertOrReplace([record], intoTable: DeferredRecord.table)
    }

    /// Removes a deferred record from the queue
    func deferredRecordDequeue(_ recordName: String) {
        try? db.delete(fromTable: DeferredRecord.table, where: DeferredRecord.Properties.recordName == recordName)
    }

    /// Updates a deferred record (typically to increment retry count)
    func deferredRecordUpdate(_ record: DeferredRecord) {
        try? db.insertOrReplace([record], intoTable: DeferredRecord.table)
    }

    /// Gets all deferred records
    func deferredRecordList() -> [DeferredRecord] {
        (try? db.getObjects(
            fromTable: DeferredRecord.table,
            orderBy: [DeferredRecord.Properties.lastAttempt.order(.ascending)]
        )) ?? []
    }

    /// Gets count of deferred records
    func deferredRecordCount() -> Int {
        (try? db.getValue(on: DeferredRecord.Properties.recordName.count(), fromTable: DeferredRecord.table))?.intValue ?? 0
    }

    /// Clears all deferred records
    func deferredRecordClear() {
        try? db.delete(fromTable: DeferredRecord.table)
    }

    /// Gets deferred records older than a specific date
    func deferredRecordFind(olderThan date: Date) -> [DeferredRecord] {
        (try? db.getObjects(
            fromTable: DeferredRecord.table,
            where: DeferredRecord.Properties.lastAttempt < date,
            orderBy: [DeferredRecord.Properties.lastAttempt.order(.ascending)]
        )) ?? []
    }
}
