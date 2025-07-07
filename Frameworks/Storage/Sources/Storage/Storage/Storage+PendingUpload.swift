//
//  Storage+PendingUpload.swift
//  Storage
//
//  Created by Alan Ye on 7/5/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    /// Adds a pending upload to the queue
    func pendingUploadEnqueue(_ upload: PendingUpload) {
        try? db.insertOrReplace([upload], intoTable: PendingUpload.table)
    }

    /// Removes a pending upload from the queue
    func pendingUploadDequeue(_ luid: String) {
        try? db.delete(fromTable: PendingUpload.table, where: PendingUpload.Properties.luid == luid)
    }

    /// Gets all pending uploads
    func pendingUploadList() -> [PendingUpload] {
        (try? db.getObjects(
            fromTable: PendingUpload.table,
            orderBy: [PendingUpload.Properties.version.order(.ascending)]
        )) ?? []
    }

    /// Gets count of pending uploads
    func pendingUploadCount() -> Int {
        (try? db.getValue(on: PendingUpload.Properties.luid.count(), fromTable: PendingUpload.table))?.intValue ?? 0
    }

    /// Clears all pending uploads
    func pendingUploadClear() {
        try? db.delete(fromTable: PendingUpload.table)
    }

    /// Gets pending uploads for a specific cloudId
    func pendingUploadFind(byCloudId cloudId: String) -> [PendingUpload] {
        (try? db.getObjects(
            fromTable: PendingUpload.table,
            where: PendingUpload.Properties.cloudId == cloudId,
            orderBy: [PendingUpload.Properties.version.order(.ascending)]
        )) ?? []
    }
}
