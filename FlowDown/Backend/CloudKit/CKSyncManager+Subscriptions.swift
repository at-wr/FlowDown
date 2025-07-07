//
//  CKSyncManager+Subscriptions.swift
//  FlowDown
//
//  Created by Alan Ye on 7/5/25.
//

import CloudKit
import Foundation
import OSLog

extension CloudKitSyncManager {
    func createDatabaseSubscription() async throws {
        let subscriptionID = "FlowDownDatabaseSubscription"

        let existingSubscriptions = try await privateDatabase.allSubscriptions()

        if existingSubscriptions.contains(where: { $0.subscriptionID == subscriptionID }) {
            logger.info("Database subscription already exists")
            return
        }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.shouldBadge = false
        notificationInfo.shouldSendMutableContent = false

        subscription.notificationInfo = notificationInfo

        do {
            _ = try await privateDatabase.save(subscription)
            logger.info("Successfully created database subscription")
        } catch {
            logger.error("Failed to create database subscription: \(error.localizedDescription)")
            throw error
        }
    }

    func createZoneSubscription() async throws {
        let subscriptionID = "FlowDownZoneSubscription"

        let existingSubscriptions = try await privateDatabase.allSubscriptions()

        if existingSubscriptions.contains(where: { $0.subscriptionID == subscriptionID }) {
            logger.info("Zone subscription already exists")
            return
        }

        let subscription = CKRecordZoneSubscription(zoneID: customZone.zoneID, subscriptionID: subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.shouldBadge = false

        subscription.notificationInfo = notificationInfo

        do {
            _ = try await privateDatabase.save(subscription)
            logger.info("Successfully created zone subscription")
        } catch {
            logger.error("Failed to create zone subscription: \(error.localizedDescription)")
            throw error
        }
    }

    func removeAllSubscriptions() async throws {
        let subscriptions = try await privateDatabase.allSubscriptions()
        let subscriptionIDs = subscriptions.map(\.subscriptionID)

        guard !subscriptionIDs.isEmpty else {
            logger.info("No subscriptions to remove")
            return
        }

        do {
            _ = try await privateDatabase.modifySubscriptions(saving: [], deleting: subscriptionIDs)
            logger.info("Successfully removed \(subscriptionIDs.count) subscriptions")
        } catch {
            logger.error("Failed to remove subscriptions: \(error.localizedDescription)")
            throw error
        }
    }
}

extension CloudKitSyncManager {
    func handleCloudKitNotification(_ notification: CKNotification) async -> UIBackgroundFetchResult {
        let notificationTypeName = String(describing: notification.notificationType)
        logger.info("Received CloudKit push notification of type: \(notificationTypeName)")

        guard syncStatus == .idle || syncStatus == .completed else {
            logger.info("Sync already in progress, skipping notification handling.")
            return .noData
        }

        switch notification.notificationType {
        case .database:
            return await handleDatabaseNotification(notification as! CKDatabaseNotification)
        case .recordZone:
            return await handleZoneNotification(notification as! CKRecordZoneNotification)
        case .query:
            return await handleQueryNotification(notification as! CKQueryNotification)
        case .readNotification:
            logger.info("Received read notification (no action needed)")
            return .noData
        @unknown default:
            logger.warning("Unknown CloudKit notification type")
            return .noData
        }
    }

    private func handleDatabaseNotification(_: CKDatabaseNotification) async -> UIBackgroundFetchResult {
        logger.info("Received database notification")

        if isUploadInProgress {
            logger.info("Upload in progress, delaying download notification handling by 5 seconds")
            try? await Task.sleep(for: .seconds(5))
        }

        do {
            let previousDataHash = calculateCurrentDataHash()

            try await downloadAndProcessChanges()

            await MainActor.run {
                lastSyncDate = Date()
            }

            let newDataHash = calculateCurrentDataHash()
            return previousDataHash != newDataHash ? .newData : .noData

        } catch {
            logger.error("Failed to handle database notification: \(error.localizedDescription)")
            await scheduleRetryWithExponentialBackoff(operation: "downloadAndProcessChanges", error: error)
            return .failed
        }
    }

    private func handleZoneNotification(_ notification: CKRecordZoneNotification) async -> UIBackgroundFetchResult {
        logger.info("Received zone notification for zone: \(notification.recordZoneID?.zoneName ?? "unknown")")

        guard let zoneID = notification.recordZoneID else {
            logger.warning("Zone notification missing zoneID")
            return .noData
        }

        do {
            let previousDataHash = calculateCurrentDataHash()

            try await fetchZoneChanges(in: [zoneID])

            try await processDeferredRecords()
            try await processDeferredRecords()

            await MainActor.run {
                lastSyncDate = Date()
            }

            let newDataHash = calculateCurrentDataHash()
            return previousDataHash != newDataHash ? .newData : .noData

        } catch {
            logger.error("Failed to handle zone notification: \(error.localizedDescription)")
            await scheduleRetryWithExponentialBackoff(operation: "downloadAndProcessChanges", error: error)
            return .failed
        }
    }

    private func handleQueryNotification(_: CKQueryNotification) async -> UIBackgroundFetchResult {
        logger.info("Received query notification")

        return await withCheckedContinuation { continuation in
            let completionObserver = NotificationCenter.default.addObserver(
                forName: .cloudKitSyncCompleted,
                object: nil,
                queue: .main
            ) { _ in
                continuation.resume(returning: .newData)
            }

            let failureObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("CloudKitSyncFailed"),
                object: nil,
                queue: .main
            ) { _ in
                continuation.resume(returning: .failed)
            }

            performFullSync()

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                NotificationCenter.default.removeObserver(completionObserver)
                NotificationCenter.default.removeObserver(failureObserver)
                continuation.resume(returning: .failed)
            }
        }
    }

    private func calculateCurrentDataHash() -> Int {
        let conversationCount = storage.conversationList().count
        let messageCount = storage.listMessages().count
        let modelCount = storage.cloudModelList().count

        return conversationCount &* 31 &+ messageCount &* 17 &+ modelCount
    }
}

extension CloudKitSyncManager {
    public func performCompaction() async {
        logger.info("Starting CloudKit data compaction")

        do {
            try await compactOldRecords()
            logger.info("Data compaction completed successfully")
        } catch {
            logger.error("Data compaction failed: \(error.localizedDescription)")
        }
    }

    private func compactOldRecords() async throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -Config.compactionDays, to: Date()) ?? Date()

        let records = try await fetchRecordsForCompaction(olderThan: cutoffDate)

        guard !records.isEmpty else {
            logger.info("No records found for compaction")
            return
        }

        logger.info("Found \(records.count) records for compaction analysis")

        let recordsToDelete = identifyRedundantRecords(from: records)

        if !recordsToDelete.isEmpty {
            try await deleteRedundantRecords(recordsToDelete)
            logger.info("Compaction completed - deleted \(recordsToDelete.count) redundant records")
        } else {
            logger.info("No redundant records found for deletion")
        }
    }

    private func fetchRecordsForCompaction(olderThan date: Date) async throws -> [CKRecord] {
        let predicate = NSPredicate(format: "version < %@", date as CVarArg)
        let query = CKQuery(recordType: "SyncObject", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "version", ascending: true)]

        return try await withCheckedThrowingContinuation { continuation in
            var allRecords: [CKRecord] = []

            func fetchBatch(cursor: CKQueryOperation.Cursor? = nil) {
                let operation = if let cursor {
                    CKQueryOperation(cursor: cursor)
                } else {
                    CKQueryOperation(query: query)
                }

                operation.zoneID = customZone.zoneID
                operation.resultsLimit = 200

                operation.recordMatchedBlock = { [weak self] _, result in
                    switch result {
                    case let .success(record):
                        allRecords.append(record)
                    case let .failure(error):
                        self?.logger.error("Error fetching record for compaction: \(error.localizedDescription)")
                    }
                }

                operation.queryResultBlock = { result in
                    switch result {
                    case let .success(cursor):
                        if let cursor {
                            fetchBatch(cursor: cursor)
                        } else {
                            continuation.resume(returning: allRecords)
                        }
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }

                self.privateDatabase.add(operation)
            }

            fetchBatch()
        }
    }

    private func identifyRedundantRecords(from records: [CKRecord]) -> [CKRecord.ID] {
        let groupedRecords = Dictionary(grouping: records) { record in
            record["cloudId"] as? String ?? ""
        }

        var recordIDsToDelete: [CKRecord.ID] = []

        for (_, recordGroup) in groupedRecords {
            guard recordGroup.count > 1 else { continue }

            let sortedRecords = recordGroup.sorted { record1, record2 in
                let date1 = record1["version"] as? Date ?? .distantPast
                let date2 = record2["version"] as? Date ?? .distantPast
                return date1 > date2
            }

            let recordsToDelete = Array(sortedRecords.dropFirst())

            if let newestRecord = sortedRecords.first,
               newestRecord["removed"] as? Bool == true
            {
                recordIDsToDelete.append(contentsOf: sortedRecords.map(\.recordID))
            } else {
                recordIDsToDelete.append(contentsOf: recordsToDelete.map(\.recordID))
            }
        }

        return recordIDsToDelete
    }

    private func deleteRedundantRecords(_ recordIDs: [CKRecord.ID]) async throws {
        let batchSize = 400
        let batches = recordIDs.chunked(into: batchSize)

        for batch in batches {
            do {
                _ = try await privateDatabase.modifyRecords(saving: [], deleting: batch)
                logger.info("Successfully deleted batch of \(batch.count) redundant records")
            } catch {
                logger.error("Failed to delete batch of redundant records: \(error.localizedDescription)")
            }
        }
    }

    func schedulePeriodicCompaction() {
        Timer.scheduledTimer(withTimeInterval: 7 * 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task {
                await self?.performCompaction()
            }
        }
    }
}
