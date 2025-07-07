//
//  DeferredRecord.swift
//  Storage
//
//  Created by Alan Ye on 7/5/25.
//

import Foundation
import WCDBSwift

/// Represents a CloudKit record that couldn't be processed due to missing dependencies
/// and is deferred for later processing once dependencies are satisfied.
public final class DeferredRecord: TableCodable {
    /// The unique CloudKit record name
    public var recordName: String = ""

    /// The serialized CKRecord data
    public var recordData: Data?

    /// Number of times we've attempted to process this record
    public var retryCount: Int = 0

    /// Last time we attempted to process this record
    public var lastAttempt: Date = .init()

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = DeferredRecord
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(recordName, isPrimary: true, isUnique: true)
            BindColumnConstraint(recordData)
            BindColumnConstraint(retryCount, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(lastAttempt, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
        }

        case recordName
        case recordData
        case retryCount
        case lastAttempt
    }

    public init() {}
}
