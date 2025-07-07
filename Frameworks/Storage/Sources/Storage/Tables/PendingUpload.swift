//
//  PendingUpload.swift
//  Storage
//
//  Created by Alan Ye on 7/5/25.
//

import Foundation
import WCDBSwift

/// Represents a local change that is pending upload to CloudKit.
///
/// This object is stored in a local database queue. A background process
/// attempts to upload these changes to CloudKit. Upon successful upload,
/// the corresponding record is removed from this queue. This ensures that
/// local changes are not lost due to network failures or app termination.
public final class PendingUpload: TableCodable {
    /// A unique local identifier for the pending upload record, acting as the primary key.
    public var luid: String = ""

    /// The logical identifier for the data entity (e.g., a specific Conversation or Message).
    /// This corresponds to the `cloudId` in the `SyncObject` on CloudKit.
    public var cloudId: String = ""

    /// The type of the data entity being changed (e.g., "Conversation", "Message").
    public var type: String = ""

    /// The timestamp of when the local change occurred.
    public var version: Date = .init()

    /// The serialized data of the entity as a binary Plist. This is `nil` for delete operations.
    public var payload: Data?

    /// A tombstone flag indicating that the logical entity should be deleted in CloudKit.
    public var removed: Bool = false

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = PendingUpload
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(luid, isPrimary: true, isUnique: true)
            BindColumnConstraint(cloudId, isNotNull: true)
            BindColumnConstraint(type, isNotNull: true)
            BindColumnConstraint(version, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(payload) // Can be null
            BindColumnConstraint(removed, isNotNull: true, defaultTo: false)
        }

        case luid
        case cloudId
        case type
        case version
        case payload
        case removed
    }

    public init() {}
}
