//
//  CKSyncManager+Download.swift
//  FlowDown
//
//  Created by Alan Ye on 7/5/25.
//

import CloudKit
import Foundation
import OSLog
import Storage

extension CloudKitSyncManager {
    func downloadRemoteChanges() async throws {
        logger.info("Starting to download remote changes")

        try await fetchDatabaseChanges()

        logger.info("Finished downloading remote changes")
    }

    func fetchDatabaseChanges() async throws {
        logger.info("Fetching database changes")

        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: serverChangeToken)
        var changedZoneIDs: [CKRecordZone.ID] = []
        var deletedZoneIDs: [CKRecordZone.ID] = []

        return try await withCheckedThrowingContinuation { continuation in
            operation.recordZoneWithIDChangedBlock = { zoneID in
                changedZoneIDs.append(zoneID)
            }

            operation.recordZoneWithIDWasDeletedBlock = { zoneID in
                deletedZoneIDs.append(zoneID)
                self.logger.info("Zone deleted: \(zoneID.zoneName)")
                self.handleZoneDeletion(zoneID)
            }

            operation.changeTokenUpdatedBlock = { token in
                self.serverChangeToken = token
                self.saveChangeTokens()
            }

            operation.fetchDatabaseChangesResultBlock = { result in
                switch result {
                case .success(let (token, moreComing)):
                    self.serverChangeToken = token
                    self.saveChangeTokens()

                    Task {
                        do {
                            if !changedZoneIDs.isEmpty {
                                try await self.fetchZoneChanges(in: changedZoneIDs)
                            }

                            if moreComing {
                                try await self.fetchDatabaseChanges()
                            }

                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            privateDatabase.add(operation)
        }
    }

    func fetchZoneChanges(in zoneIDs: [CKRecordZone.ID]) async throws {
        logger.info("Fetching changes for \(zoneIDs.count) zones")

        var configurationsByZoneID: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]

        for zoneID in zoneIDs {
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = zoneChangeTokens[zoneID]
            configurationsByZoneID[zoneID] = configuration
        }

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: zoneIDs,
            configurationsByRecordZoneID: configurationsByZoneID
        )

        var fetchedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []
        var currentCount = 0

        return try await withCheckedThrowingContinuation { continuation in
            operation.recordWasChangedBlock = { [weak self] recordID, result in
                switch result {
                case let .success(record):
                    fetchedRecords.append(record)
                    currentCount += 1

                    Task { @MainActor in
                        self?.syncStatus = .downloading(currentCount, max(currentCount + 50, 100))
                    }

                case let .failure(error):
                    self?.logger.error("Error fetching record \(recordID.recordName): \(error.localizedDescription)")
                }
            }

            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                deletedRecordIDs.append(recordID)
            }

            operation.recordZoneChangeTokensUpdatedBlock = { [weak self] zoneID, token, _ in
                if let token {
                    self?.zoneChangeTokens[zoneID] = token
                    self?.saveChangeTokens()
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    Task {
                        await self.processDownloadedRecords(fetchedRecords)
                        await self.processDeletedRecords(deletedRecordIDs)
                        continuation.resume()
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            self.privateDatabase.add(operation)
        }
    }

    func processDownloadedRecords(_ records: [CKRecord]) async {
        guard !records.isEmpty else { return }

        logger.info("Processing \(records.count) downloaded records")

        await MainActor.run {
            self.syncStatus = .processing
        }

        let sortedRecords = records.sorted {
            ($0["version"] as? Date ?? .distantPast) < ($1["version"] as? Date ?? .distantPast)
        }

        var deferredRecords: [CKRecord] = []
        var processedCount = 0

        for record in sortedRecords {
            do {
                try await processDownloadedRecord(record)
                processedCount += 1
            } catch let ProcessingError.dependencyMissing(message) {
                logger.info("Dependency missing for record, deferring: \(message)")
                deferredRecords.append(record)
            } catch {
                logger.error("Failed to process record \(record.recordID.recordName): \(error.localizedDescription)")
            }
        }

        if !deferredRecords.isEmpty {
            logger.info("Storing \(deferredRecords.count) deferred records for later processing")
            await storeDeferredRecords(deferredRecords)
        }

        let finalProcessedCount = processedCount
        logger.info("Processed \(finalProcessedCount) records, deferred \(deferredRecords.count)")

        if finalProcessedCount > 0 {
            await MainActor.run {
                ConversationManager.shared.scanAll()
                NotificationCenter.default.post(name: .cloudKitDataProcessed, object: finalProcessedCount)
            }
        }
    }

    func processDownloadedRecord(_ record: CKRecord) async throws {
        logger.info("Processing record: \(record.recordID.recordName), recordType: \(record.recordType)")
        logger.info("Record keys: \(record.allKeys())")

        let recordId = record.recordID.recordName
        let recordDeviceId = record["deviceId"] as? String

        if let recordDeviceId, recordDeviceId == CloudKitSyncManager.shared.deviceId {
            logger.info("Skipping record uploaded by this device to prevent overwrite: \(recordId) (device: \(recordDeviceId))")
            return
        }

        if recordDeviceId == nil, wasRecentlyUploaded(recordId: recordId) {
            logger.info("Skipping recently uploaded record (no deviceId) to prevent overwrite: \(recordId)")
            return
        }

        guard record.recordType == "SyncObject" else {
            logger.info("Skipping non-sync record: \(record.recordType)")
            return
        }

        guard let cloudId = record["cloudId"] as? String, !cloudId.isEmpty else {
            logger.error("Record missing cloudId field or empty: \(record.allKeys())")
            throw ProcessingError.recordDataMissing("cloudId")
        }

        guard let type = record["type"] as? String, !type.isEmpty else {
            logger.error("Record missing type field or empty: \(record.allKeys())")
            throw ProcessingError.recordDataMissing("type")
        }

        guard let version = record["version"] as? Date else {
            logger.error("Record missing version field or wrong type: \(record.allKeys())")
            throw ProcessingError.recordDataMissing("version")
        }

        let isRemoved = record["removed"] as? Bool ?? false

        if isRemoved {
            try await handleRemoteDelete(cloudId: cloudId, type: type)
        } else {
            guard let payload = record["payload"] as? Data else {
                logger.error("Record missing payload field or wrong type: \(record.allKeys())")
                if let payloadValue = record["payload"] {
                    logger.error("Payload value type: \(Swift.type(of: payloadValue))")
                }
                throw ProcessingError.recordDataMissing("payload")
            }
            try await handleRemoteUpsert(cloudId: cloudId, type: type, payload: payload, version: version, deviceId: recordDeviceId)
        }
    }

    func handleRemoteDelete(cloudId: String, type: String) async throws {
        logger.info("Processing remote delete: \(type) \(cloudId)")

        switch type {
        case Conversation.syncableType:
            if let conversation = storage.findConversation(byCloudId: cloudId) {
                storage.conversationRemove(conversationWith: conversation.id)
            }

        case Message.syncableType:
            if let message = storage.findMessage(byCloudId: cloudId) {
                storage.delete(messageIdentifier: message.id)
            }

        case Attachment.syncableType:
            storage.attachmentRemove(byCloudId: cloudId)

        case CloudModel.syncableType:
            storage.cloudModelRemove(identifier: cloudId)

        default:
            throw ProcessingError.unsupportedType(type)
        }
    }

    func handleRemoteUpsert(cloudId: String, type: String, payload: Data, version: Date, deviceId: String?) async throws {
        logger.info("Processing remote upsert: \(type) \(cloudId)")

        let decoder = PropertyListDecoder()

        switch type {
        case Conversation.syncableType:
            let conversationPayload = try decoder.decode(ConversationPayload.self, from: payload)
            try await upsertConversation(from: conversationPayload, version: version, deviceId: deviceId)

        case Message.syncableType:
            let messagePayload = try decoder.decode(MessagePayload.self, from: payload)
            try await upsertMessage(from: messagePayload, version: version, deviceId: deviceId)

        case Attachment.syncableType:
            let attachmentPayload = try decoder.decode(AttachmentPayload.self, from: payload)
            try await upsertAttachment(from: attachmentPayload, version: version, deviceId: deviceId)

        case CloudModel.syncableType:
            let cloudModelPayload = try decoder.decode(CloudModelPayload.self, from: payload)
            try await upsertCloudModel(from: cloudModelPayload, version: version, deviceId: deviceId)

        default:
            throw ProcessingError.unsupportedType(type)
        }
    }

    func processDeletedRecords(_ deletedRecordIDs: [CKRecord.ID]) async {
        guard !deletedRecordIDs.isEmpty else { return }

        logger.info("Processing \(deletedRecordIDs.count) deleted records")

        for recordID in deletedRecordIDs {
            let cloudId = recordID.recordName

            let pendingUploads = storage.pendingUploadFind(byCloudId: cloudId)
            if !pendingUploads.isEmpty {
                logger.info("Found and removed \(pendingUploads.count) pending uploads for deleted record \(cloudId)")
                for upload in pendingUploads {
                    storage.pendingUploadDequeue(upload.luid)
                }
            }

            if let conversation = storage.findConversation(byCloudId: cloudId) {
                storage.conversationRemove(conversationWith: conversation.id)
            } else if let message = storage.findMessage(byCloudId: cloudId) {
                storage.delete(messageIdentifier: message.id)
            } else {
                storage.attachmentRemove(byCloudId: cloudId)
                storage.cloudModelRemove(identifier: cloudId)
            }
        }
    }

    func handleZoneDeletion(_ zoneID: CKRecordZone.ID) {
        if zoneID == customZone.zoneID {
            logger.warning("Custom zone was deleted - resetting local sync state")

            serverChangeToken = nil
            zoneChangeTokens.removeAll()
            storage.pendingUploadClear()

            UserDefaults.standard.removeObject(forKey: "CloudKitFirstTimeSetupComplete")
            isFirstTimeSetup = true
        }
    }
}

extension CloudKitSyncManager {
    func storeDeferredRecords(_ records: [CKRecord]) async {
        for record in records {
            let deferredRecord = DeferredRecord()
            deferredRecord.recordName = record.recordID.recordName
            deferredRecord.recordData = try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
            deferredRecord.retryCount = 0
            deferredRecord.lastAttempt = Date()

            storage.deferredRecordEnqueue(deferredRecord)
        }
    }

    func processDeferredRecords() async throws {
        let deferredRecords = storage.deferredRecordList()

        guard !deferredRecords.isEmpty else {
            logger.info("No deferred records to process")
            return
        }

        logger.info("Processing \(deferredRecords.count) deferred records")

        var processedRecords: [DeferredRecord] = []
        var stillDeferred: [DeferredRecord] = []

        for deferredRecord in deferredRecords {
            guard let recordData = deferredRecord.recordData,
                  let record = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: recordData)
            else {
                storage.deferredRecordDequeue(deferredRecord.recordName)
                continue
            }

            do {
                try await processDownloadedRecord(record)
                processedRecords.append(deferredRecord)
            } catch ProcessingError.dependencyMissing {
                deferredRecord.retryCount += 1
                deferredRecord.lastAttempt = Date()

                if deferredRecord.retryCount >= 10 {
                    logger.warning("Giving up on deferred record after 10 retries: \(deferredRecord.recordName)")
                    storage.deferredRecordDequeue(deferredRecord.recordName)
                } else {
                    stillDeferred.append(deferredRecord)
                }
            } catch {
                logger.error("Failed to process deferred record: \(error.localizedDescription)")
                storage.deferredRecordDequeue(deferredRecord.recordName)
            }
        }

        for record in processedRecords {
            storage.deferredRecordDequeue(record.recordName)
        }

        for record in stillDeferred {
            storage.deferredRecordUpdate(record)
        }

        logger.info("Processed \(processedRecords.count) deferred records, \(stillDeferred.count) still deferred")
    }
}

enum ProcessingError: LocalizedError {
    case recordDataMissing(String)
    case unsupportedType(String)
    case dependencyMissing(String)

    var errorDescription: String? {
        switch self {
        case let .recordDataMissing(field):
            "Record data missing: \(field)"
        case let .unsupportedType(type):
            "Unsupported record type: \(type)"
        case let .dependencyMissing(message):
            "Dependency missing: \(message)"
        }
    }
}
