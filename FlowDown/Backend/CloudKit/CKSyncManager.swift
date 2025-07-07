//
//  CKSyncManager.swift
//  FlowDown
//
//  Created by Alan Ye on 7/5/25.
//

import BackgroundTasks
import CloudKit
import Combine
import Foundation
import OSLog
import Storage
import UIKit

// Needs further rework qwq

final class CloudKitSyncManager: ObservableObject, @unchecked Sendable {
    static let shared = CloudKitSyncManager()

    enum Config {
        static let customZoneName = "FlowDownSyncZone"
        static let backgroundTaskIdentifier = "wiki.qaq.flowdown.cloudsync"
        static let maxRetryAttempts = 5
        static let retryBackoffBase: TimeInterval = 2.0
        static let compactionDays = 30
    }

    let logger = Logger(subsystem: "wiki.qaq.flowdown", category: "CloudKitSyncManager")
    let privateDatabase = CKContainer.default().privateCloudDatabase
    let storage: Storage
    lazy var customZone = CKRecordZone(zoneName: Config.customZoneName)

    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var isFirstTimeSetup: Bool = true

    var serverChangeToken: CKServerChangeToken? {
        didSet { saveServerChangeToken() }
    }

    var zoneChangeTokens: [CKRecordZone.ID: CKServerChangeToken] = [:] {
        didSet { saveZoneChangeTokens() }
    }

    var backgroundTask: BGProcessingTask?
    var cancellables = Set<AnyCancellable>()
    private var lastSyncTrigger: [String: Date] = [:]
    private let syncDebounceInterval: TimeInterval = 0.5
    private let syncQueue = DispatchQueue(label: "com.flowdown.cloudkit.sync", attributes: .concurrent)
    private var isFullSyncInProgress = false
    var isUploadInProgress = false
    private var retryAttempts: [String: Int] = [:]
    private var lastRetryTime: [String: Date] = [:]

    let deviceId: String = {
        let key = "CloudKitSyncDeviceId"
        if let existingId = UserDefaults.standard.string(forKey: key) {
            return existingId
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: key)
            return newId
        }
    }()

    private var recentlyUploadedRecords = Set<String>()
    private var uploadTimestamps: [String: Date] = [:]
    private let recentUploadTimeWindow: TimeInterval = 30.0

    private init() {
        guard let storageInstance = try? Storage.db() else {
            fatalError("Failed to initialize local storage for CloudKitSyncManager.")
        }
        storage = storageInstance

        loadPersistedTokens()
        setupBackgroundTasks()
        setupAutoSync()
        setupSyncNotifications()

        isFirstTimeSetup = UserDefaults.standard.object(forKey: "CloudKitFirstTimeSetupComplete") == nil
    }

    private func setupSyncNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FlowDown.MessageDidUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.object as? Message {
                self?.syncLocalChange(for: message, changeType: .update)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FlowDown.ConversationDidUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let conversation = notification.object as? Conversation {
                self?.syncLocalChange(for: conversation, changeType: .update)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FlowDown.AttachmentDidUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let attachment = notification.object as? Attachment {
                self?.syncLocalChange(for: attachment, changeType: .update)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FlowDown.CloudModelDidUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let cloudModel = notification.object as? CloudModel {
                self?.syncLocalChange(for: cloudModel, changeType: .update)
            }
        }
    }

    public func performFullSync() {
        guard syncStatus != .syncing else {
            logger.info("Sync already in progress, skipping")
            return
        }

        Task {
            await performFullSyncAsync()
        }
    }

    public func performFirstTimeSetup() async throws {
        logger.info("Starting first-time CloudKit setup")

        await MainActor.run {
            syncStatus = .settingUp
            showSetupAlert()
        }

        do {
            try await createCustomZoneIfNeeded()
            try await createDatabaseSubscription()
            try await createZoneSubscription()
            var retryCount = 0
            let maxRetries = 3

            while retryCount < maxRetries {
                do {
                    try await performInitialDataFetchWithThrows()
                    break
                } catch {
                    retryCount += 1
                    if retryCount >= maxRetries {
                        throw error
                    }
                    logger.warning("Initial data fetch retry \(retryCount)/\(maxRetries)")
                    try await Task.sleep(for: .seconds(2))
                }
            }

            try await processDeferredRecords()
            try await processDeferredRecords()
            await ensureIntroductionConversation()
            UserDefaults.standard.set(true, forKey: "CloudKitFirstTimeSetupComplete")
            isFirstTimeSetup = false

            await MainActor.run {
                syncStatus = .completed
                hideSetupAlert()
                ConversationManager.shared.scanAll()
                ModelManager.shared.refreshCloudModels()
                NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: nil)
            }

            logger.info("First-time setup completed successfully")

            Task {
                try? await Task.sleep(for: .seconds(5))
                logger.info("Performing post-setup sync to catch any missed updates")
                try? await downloadRemoteChanges()
                try? await Task.sleep(for: .seconds(15))
                logger.info("Performing final post-setup sync")
                try? await downloadRemoteChanges()
            }

        } catch {
            await MainActor.run {
                syncStatus = .failed(error)
                hideSetupAlert()
                showSetupErrorAlert(error)
            }
            logger.error("First-time setup failed: \(error.localizedDescription)")
            throw error
        }
    }

    @MainActor
    private func showSetupAlert() {
        logger.info("Showing CloudKit setup progress to user")
    }

    @MainActor
    private func hideSetupAlert() {
        logger.info("Hiding CloudKit setup progress")
    }

    @MainActor
    private func showSetupErrorAlert(_ error: Error) {
        logger.error("Showing setup error to user: \(error.localizedDescription)")
    }

    public func syncLocalChange(for object: any Syncable, changeType: LocalChangeType) {
        if let conversation = object as? Conversation, conversation.cloudId == "local-introduction" {
            logger.debug("Skipping sync for introduction conversation")
            return
        }

        let objectKey = "\(Swift.type(of: object))_\(object.cloudId)"
        let now = Date()

        if let lastTrigger = lastSyncTrigger[objectKey],
           now.timeIntervalSince(lastTrigger) < syncDebounceInterval,
           changeType != .delete
        {
            logger.debug("Debouncing sync call for \(Swift.type(of: object)) \(object.cloudId)")
            return
        }

        lastSyncTrigger[objectKey] = now

        DispatchQueue.global(qos: .background).async {
            self.enqueuePendingUpload(for: object, changeType: changeType)
        }
    }

    public func refresh() {
        let timeSinceLastSync = lastSyncDate?.timeIntervalSinceNow ?? -Double.greatestFiniteMagnitude

        if timeSinceLastSync > -300 {
            performIncrementalRefresh()
        } else {
            performFullSync()
        }
    }

    public func performIncrementalRefresh() {
        guard syncStatus == .idle || syncStatus == .completed else {
            logger.info("Sync already in progress, skipping incremental refresh")
            return
        }

        Task {
            logger.info("Starting incremental refresh")

            await MainActor.run {
                syncStatus = .syncing
            }

            do {
                if storage.pendingUploadCount() > 0 {
                    try await uploadPendingChanges()
                }

                try await downloadRemoteChanges()
                try await processDeferredRecords()

                await MainActor.run {
                    self.lastSyncDate = Date()
                    self.syncStatus = .completed
                    NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: nil)
                }

                logger.info("Incremental refresh completed successfully")

            } catch {
                await MainActor.run {
                    syncStatus = .failed(error)
                }
                logger.error("Incremental refresh failed: \(error.localizedDescription)")
            }
        }
    }

    public func forceSyncLocalChange(for object: any Syncable, changeType: LocalChangeType) {
        if let conversation = object as? Conversation, conversation.cloudId == "local-introduction" {
            logger.debug("Skipping force sync for introduction conversation")
            return
        }

        logger.info("Force syncing \(Swift.type(of: object)) \(object.cloudId)")
        DispatchQueue.global(qos: .background).async {
            self.enqueuePendingUpload(for: object, changeType: changeType)
        }
    }

    public func performTestSync() async {
        logger.info("=== DEVELOPMENT TEST SYNC STARTED ===")

        let startTime = Date()

        await performFullSyncAsync()

        let duration = Date().timeIntervalSince(startTime)
        logger.info("=== TEST SYNC COMPLETED in \(String(format: "%.2f", duration))s ===")

        let conversations = storage.conversationList()
        let messages = storage.listMessages()
        let pendingUploads = storage.pendingUploadList()

        logger.info("Sync Statistics:")
        logger.info("- Conversations: \(conversations.count)")
        logger.info("- Messages: \(messages.count)")
        logger.info("- Pending uploads: \(pendingUploads.count)")
        logger.info("- Last sync: \(lastSyncDate?.formatted() ?? "Never")")
        logger.info("- Status: \(String(describing: syncStatus))")
    }

    public func forceResyncRecentMessages() {
        logger.info("Force resyncing recent messages to recover from upload failures")

        let recentMessages = storage.listMessages().filter { message in
            abs(message.lastModified.timeIntervalSinceNow) < 3600
        }

        logger.info("Found \(recentMessages.count) recent messages to resync")

        for message in recentMessages {
            logger.info("Force resyncing message: \(message.cloudId)")
            forceSyncLocalChange(for: message, changeType: .update)
        }

        let recentConversations = storage.conversationList().filter { conversation in
            abs(conversation.lastModified.timeIntervalSinceNow) < 3600
        }

        logger.info("Found \(recentConversations.count) recent conversations to resync")

        for conversation in recentConversations {
            logger.info("Force resyncing conversation: \(conversation.cloudId)")
            forceSyncLocalChange(for: conversation, changeType: .update)
        }
    }
}

extension CloudKitSyncManager {
    enum SyncStatus: Equatable {
        case idle
        case settingUp
        case syncing
        case uploading(Int, Int) // current, total
        case downloading(Int, Int) // current, total
        case processing
        case completed
        case failed(Error)

        static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.settingUp, .settingUp), (.syncing, .syncing), (.processing, .processing), (.completed, .completed):
                true
            case let (.uploading(l1, l2), .uploading(r1, r2)):
                l1 == r1 && l2 == r2
            case let (.downloading(l1, l2), .downloading(r1, r2)):
                l1 == r1 && l2 == r2
            case (.failed(_), .failed(_)):
                true // We'll consider all failed states equal for UI purposes
            default:
                false
            }
        }
    }

    enum LocalChangeType {
        case create, update, delete
    }
}

extension CloudKitSyncManager {
    func performFullSyncAsync() async {
        var shouldProceed = false
        syncQueue.sync(flags: .barrier) {
            if !isFullSyncInProgress {
                isFullSyncInProgress = true
                shouldProceed = true
            }
        }

        guard shouldProceed else {
            logger.info("Full sync already in progress, skipping")
            return
        }

        defer {
            syncQueue.sync(flags: .barrier) {
                isFullSyncInProgress = false
            }
        }

        logger.info("Starting full CloudKit sync")

        await MainActor.run {
            syncStatus = .syncing
        }

        do {
            try await createCustomZoneIfNeeded()
            try await uploadPendingChanges()
            try await downloadAndProcessChanges()

            await MainActor.run {
                self.lastSyncDate = Date()
                self.syncStatus = .completed
                NotificationCenter.default.post(name: .cloudKitSyncCompleted, object: nil)
            }

            ConversationManager.shared.scanAll()

            logger.info("Full sync completed successfully")

        } catch {
            await MainActor.run {
                syncStatus = .failed(error)
                NotificationCenter.default.post(name: NSNotification.Name("CloudKitSyncFailed"), object: error)
            }
            logger.error("Full sync failed: \(error.localizedDescription)")
        }
    }

    func downloadAndProcessChanges() async throws {
        try await downloadRemoteChanges()
        try await processDeferredRecords()
        try await processDeferredRecords()
    }

    func createCustomZoneIfNeeded() async throws {
        let existingZones = try await privateDatabase.allRecordZones()

        if !existingZones.contains(where: { $0.zoneID == customZone.zoneID }) {
            logger.info("Creating custom CloudKit zone: \(Config.customZoneName)")
            _ = try await privateDatabase.save(customZone)
            logger.info("Custom zone created successfully")
        } else {
            logger.info("Custom zone already exists")
        }
    }

    func performInitialDataFetch() async {
        do {
            try await performInitialDataFetchWithThrows()
        } catch {
            logger.error("Initial data fetch failed: \(error.localizedDescription)")
        }
    }

    func performInitialDataFetchWithThrows() async throws {
        logger.info("Performing initial data fetch")
        await MainActor.run {
            syncStatus = .downloading(0, 1)
        }

        try await downloadRemoteChanges()
    }

    func ensureIntroductionConversation() async {
        await MainActor.run {
            let uiConversations = ConversationManager.shared.conversations.value
            let dbConversations = storage.conversationList()

            let realConversations = dbConversations.filter { conversation in
                conversation.title != "Introduction to FlowDown" &&
                    !conversation.title.contains("Introduction") &&
                    conversation.cloudId != "local-introduction"
            }

            logger.info("Found \(uiConversations.count) UI conversations, \(dbConversations.count) DB conversations, \(realConversations.count) real conversations")

            if realConversations.isEmpty, uiConversations.isEmpty {
                logger.info("Creating introduction conversation for first device")
                ConversationManager.shouldShowGuideMessage = true
                let introConv = ConversationManager.shared.createNewConversation()
                logger.info("Created introduction conversation with ID: \(introConv.id)")
            } else {
                logger.info("Found existing real conversations, skipping introduction")
                ConversationManager.shouldShowGuideMessage = false
            }
        }
    }
}

extension CloudKitSyncManager {
    func enqueuePendingUpload(for object: any Syncable, changeType: LocalChangeType) {
        var mutableObject = object

        let objectTypeName = String(describing: Swift.type(of: mutableObject))

        if mutableObject.cloudId.isEmpty, changeType == .create {
            mutableObject.cloudId = UUID().uuidString
            logger.info("Generated new cloudId: \(mutableObject.cloudId)")
            updateOriginalObjectCloudId(object, newCloudId: mutableObject.cloudId)
            logger.info("Updated original object with cloudId: \(mutableObject.cloudId)")
        } else if !mutableObject.cloudId.isEmpty, changeType == .create {
            logger.info("Object already has cloudId: \(mutableObject.cloudId)")
        }

        guard !mutableObject.cloudId.isEmpty else {
            logger.error("Cannot enqueue upload: cloudId is empty for \(objectTypeName)")
            return
        }

        let objectSyncableType = Swift.type(of: mutableObject).syncableType
        let pendingUpload: PendingUpload

        if let existingUpload = storage.pendingUploadFind(byCloudId: mutableObject.cloudId).first(where: { $0.type == objectSyncableType }) {
            logger.info("Updating existing pending upload for \(objectTypeName) \(mutableObject.cloudId)")
            pendingUpload = existingUpload

            let existingIsDelete = pendingUpload.removed
            let newIsDelete = (changeType == .delete)

            if existingIsDelete == newIsDelete {
                logger.info("Skipping duplicate operation: \(String(describing: changeType)) for \(objectTypeName) \(mutableObject.cloudId)")
                return
            }
        } else {
            pendingUpload = PendingUpload()
            pendingUpload.luid = UUID().uuidString
            pendingUpload.cloudId = mutableObject.cloudId
            pendingUpload.type = objectSyncableType
        }

        pendingUpload.version = Date()
        pendingUpload.removed = (changeType == .delete)

        if changeType == .delete {
            pendingUpload.payload = nil
        }

        guard !pendingUpload.cloudId.isEmpty else {
            logger.error("Cannot save pending upload: cloudId became empty")
            return
        }

        storage.pendingUploadEnqueue(pendingUpload)
        logger.info("Enqueued pending upload: \(String(describing: changeType)) \(objectTypeName) \(mutableObject.cloudId)")
        scheduleUploadIfNeeded()
    }

    func uploadPendingChanges() async throws {
        var shouldProceed = false
        syncQueue.sync(flags: .barrier) {
            if !isUploadInProgress {
                isUploadInProgress = true
                shouldProceed = true
            }
        }

        guard shouldProceed else {
            logger.info("Upload already in progress, skipping")
            return
        }

        defer {
            syncQueue.sync(flags: .barrier) {
                isUploadInProgress = false
            }
        }

        cleanupInvalidPendingUploads()

        let allPendingUploads = storage.pendingUploadList()
        guard !allPendingUploads.isEmpty else {
            logger.info("No pending uploads to process")
            return
        }

        logger.info("Starting upload of \(allPendingUploads.count) pending changes in passes.")

        let uploadOrder: [String] = [
            CloudModel.syncableType,
            Conversation.syncableType,
            Message.syncableType,
            Attachment.syncableType,
        ]

        let totalToUpload = allPendingUploads.count
        var totalUploadedCount = 0

        await MainActor.run {
            self.syncStatus = .uploading(0, totalToUpload)
        }

        for type in uploadOrder {
            let uploadsForType = allPendingUploads.filter { $0.type == type }
            guard !uploadsForType.isEmpty else { continue }

            logger.info("Uploading \(uploadsForType.count) changes of type '\(type)'")

            let batchSize = 400
            let batches = uploadsForType.chunked(into: batchSize)

            for batch in batches {
                do {
                    let uploadedInBatch = try await uploadBatch(batch)
                    totalUploadedCount += uploadedInBatch
                    let currentCount = totalUploadedCount

                    await MainActor.run {
                        self.syncStatus = .uploading(currentCount, totalToUpload)
                    }
                } catch {
                    logger.error("Failed to upload batch for type \(type): \(error.localizedDescription)")
                }
            }
        }

        if totalUploadedCount >= totalToUpload {
            logger.info("All pending uploads completed successfully.")
        } else {
            logger.info("Completed upload pass. \(totalToUpload - totalUploadedCount) items remain (likely due to missing dependencies).")
        }
    }

    func uploadBatch(_ batch: [PendingUpload]) async throws -> Int {
        logger.info("Processing batch with \(batch.count) pending uploads.")

        var recordsToSave: [CKRecord] = []
        var validUploadsInBatch: [PendingUpload] = []
        var seenCloudIds = Set<String>()

        let sortedBatch = batch.sorted { $0.luid < $1.luid }

        for upload in sortedBatch {
            if seenCloudIds.contains(upload.cloudId) {
                logger.warning("Skipping duplicate upload in batch: \(upload.type) \(upload.cloudId)")
                validUploadsInBatch.append(upload)
                continue
            }

            do {
                if let record = try createCloudKitRecord(from: upload) {
                    recordsToSave.append(record)
                    validUploadsInBatch.append(upload)
                    seenCloudIds.insert(upload.cloudId)
                }
            } catch {
                logger.warning("Skipping upload for now: \(upload.type) \(upload.cloudId) - reason: \(error.localizedDescription)")
            }
        }

        guard !recordsToSave.isEmpty else {
            logger.warning("No valid records to upload in this batch (all items were skipped).")
            return 0
        }

        logger.info("Uploading batch with \(recordsToSave.count) records.")

        do {
            let (savedRecords, _) = try await privateDatabase.modifyRecords(saving: recordsToSave, deleting: [])

            logger.info("Successfully saved \(savedRecords.count) records in batch.")

            for (recordID, _) in savedRecords {
                if let upload = validUploadsInBatch.first(where: { $0.cloudId == recordID.recordName }) {
                    storage.pendingUploadDequeue(upload.luid)
                    logger.debug("Dequeued: \(upload.type) \(upload.cloudId)")
                    trackRecentUpload(recordId: upload.cloudId)
                }
            }

            return savedRecords.count

        } catch {
            logger.error("Failed to upload batch: \(error.localizedDescription)")

            if let ckError = error as? CKError {
                switch ckError.code {
                case .serverRecordChanged:
                    logger.warning("CloudKit conflict detected. Triggering sync to resolve conflicts.")

                    Task {
                        do {
                            try await downloadRemoteChanges()
                            logger.info("Downloaded latest changes to resolve conflicts")
                        } catch {
                            logger.error("Failed to download changes for conflict resolution: \(error.localizedDescription)")
                        }
                    }

                    return 0

                case .quotaExceeded, .zoneBusy, .limitExceeded:
                    logger.warning("CloudKit quota/limit error: \(ckError.localizedDescription). Will retry later.")
                    return 0

                default:
                    if !ckError.isRetryable {
                        logger.error("Non-retryable CloudKit error: \(ckError.localizedDescription). Removing uploads to prevent sync loop.")
                        for upload in validUploadsInBatch {
                            storage.pendingUploadDequeue(upload.luid)
                        }
                        return validUploadsInBatch.count
                    }
                }
            }
            throw error
        }
    }

    func createCloudKitRecord(from upload: PendingUpload) throws -> CKRecord? {
        guard !upload.cloudId.isEmpty else {
            logger.error("Cannot create CloudKit record: cloudId is empty for type \(upload.type), luid: \(upload.luid). Removing invalid upload.")
            storage.pendingUploadDequeue(upload.luid)
            return nil
        }

        let recordID = CKRecord.ID(recordName: upload.cloudId, zoneID: customZone.zoneID)
        let record = CKRecord(recordType: "SyncObject", recordID: recordID)

        record["cloudId"] = upload.cloudId as CKRecordValue
        record["type"] = upload.type as CKRecordValue
        record["version"] = upload.version as CKRecordValue
        record["removed"] = upload.removed as CKRecordValue
        record["deviceId"] = deviceId as CKRecordValue

        if !upload.removed {
            record["payload"] = try createPayload(for: upload)
        }

        logger.info("Created CloudKit record: SyncObject with ID \(upload.cloudId)")
        return record
    }

    private func createPayload(for upload: PendingUpload) throws -> Data {
        guard let object = findSyncableObject(for: upload) else {
            throw NSError(domain: "CloudKitSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "Local object not found for pending upload: \(upload.type) \(upload.cloudId)"])
        }

        do {
            return try object.createPayload(storage: storage)
        } catch let error as NSError where error.domain == "CloudKitSync" && error.code == 1 {
            logger.info("Dependency missing for \(upload.type) \(upload.cloudId), attempting resolution")

            if upload.type == Message.syncableType, let message = object as? Message {
                if let conversation = storage.conversationWith(identifier: message.conversationId) {
                    if conversation.cloudId.isEmpty {
                        storage.conversationEdit(identifier: conversation.id) { conv in
                            if conv.cloudId.isEmpty {
                                conv.cloudId = UUID().uuidString
                            }
                        }

                        if let updatedConv = storage.conversationWith(identifier: conversation.id) {
                            CloudKitSyncManager.shared.syncLocalChange(for: updatedConv, changeType: .create)
                        }
                    }
                }
            }

            throw error
        }
    }

    private func findSyncableObject(for upload: PendingUpload) -> (any Syncable)? {
        switch upload.type {
        case Conversation.syncableType:
            return storage.findConversation(byCloudId: upload.cloudId)
        case Message.syncableType:
            return storage.findMessage(byCloudId: upload.cloudId)
        case Attachment.syncableType:
            return storage.findAttachment(byCloudId: upload.cloudId)
        case CloudModel.syncableType:
            return storage.findCloudModel(byCloudId: upload.cloudId)
        default:
            logger.error("Unknown syncable type in upload queue: \(upload.type)")
            return nil
        }
    }

    func scheduleUploadIfNeeded() {
        let pendingCount = storage.pendingUploadCount()
        let timeSinceLastSync = lastSyncDate?.timeIntervalSinceNow ?? -Double.greatestFiniteMagnitude

        if pendingCount >= 1 || timeSinceLastSync < -10 {
            logger.info("Scheduling upload: \(pendingCount) pending uploads, last sync: \(String(format: "%.1f", -timeSinceLastSync))s ago")
            Task {
                do {
                    try await self.uploadPendingChanges()
                } catch {
                    logger.error("Scheduled upload failed: \(error.localizedDescription)")
                    await self.scheduleRetryWithExponentialBackoff(operation: "uploadPendingChanges", error: error)
                }
            }
        } else {
            logger.debug("Not scheduling upload: \(pendingCount) pending uploads, last sync: \(String(format: "%.1f", -timeSinceLastSync))s ago")
        }
    }

    func updateOriginalObjectCloudId(_ object: any Syncable, newCloudId: String) {
        let objectTypeName = String(describing: type(of: object))
        logger.info("Updating cloudId for \(objectTypeName) to: \(newCloudId)")

        switch object {
        case let conversation as Conversation:
            storage.conversationEdit(identifier: conversation.id) { conv in
                conv.cloudId = newCloudId
            }
            logger.info("Updated conversation cloudId via conversationEdit")

        case let message as Message:
            let updatedMessage = message
            updatedMessage.cloudId = newCloudId
            storage.insertOrReplace(messages: [updatedMessage])
            logger.info("Updated message cloudId via insertOrReplace")

        case let attachment as Attachment:
            let updatedAttachment = attachment
            updatedAttachment.cloudId = newCloudId
            storage.attachmentsUpdate([updatedAttachment])
            logger.info("Updated attachment cloudId via attachmentsUpdate")

        case let cloudModel as CloudModel:
            let updatedModel = cloudModel
            updatedModel.cloudId = newCloudId
            storage.cloudModelPut(updatedModel)
            logger.info("Updated cloudModel cloudId via cloudModelPut")

        default:
            logger.warning("Unknown syncable type for cloudId update: \(objectTypeName)")
        }
    }

    func cleanupInvalidPendingUploads() {
        let allUploads = storage.pendingUploadList()
        let invalidUploads = allUploads.filter(\.cloudId.isEmpty)

        if !invalidUploads.isEmpty {
            logger.warning("Found \(invalidUploads.count) pending uploads with empty cloudIds, removing them")
            for upload in invalidUploads {
                storage.pendingUploadDequeue(upload.luid)
            }
        }
    }
}

extension CloudKitSyncManager {
    func saveChangeTokens() {
        saveServerChangeToken()
        saveZoneChangeTokens()
    }

    func saveServerChangeToken() {
        guard let token = serverChangeToken else {
            UserDefaults.standard.removeObject(forKey: "CloudKitServerChangeToken")
            return
        }

        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: "CloudKitServerChangeToken")
            logger.debug("Saved server change token")
        } catch {
            logger.error("Failed to save server change token: \(error.localizedDescription)")
        }
    }

    func saveZoneChangeTokens() {
        guard !zoneChangeTokens.isEmpty else {
            UserDefaults.standard.removeObject(forKey: "CloudKitZoneChangeTokens")
            return
        }

        var tokenData: [String: Data] = [:]

        for (zoneID, token) in zoneChangeTokens {
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                tokenData[zoneID.zoneName] = data
            } catch {
                logger.error("Failed to archive zone token for \(zoneID.zoneName): \(error.localizedDescription)")
            }
        }

        UserDefaults.standard.set(tokenData, forKey: "CloudKitZoneChangeTokens")
        logger.debug("Saved zone change tokens for \(tokenData.count) zones")
    }

    func loadPersistedTokens() {
        loadServerChangeToken()
        loadZoneChangeTokens()
    }

    private func loadServerChangeToken() {
        guard let data = UserDefaults.standard.data(forKey: "CloudKitServerChangeToken") else {
            logger.info("No saved server change token found")
            return
        }

        do {
            serverChangeToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
            logger.info("Loaded server change token")
        } catch {
            logger.error("Failed to load server change token: \(error.localizedDescription)")
        }
    }

    private func loadZoneChangeTokens() {
        guard let tokenData = UserDefaults.standard.object(forKey: "CloudKitZoneChangeTokens") as? [String: Data] else {
            logger.info("No saved zone change tokens found")
            return
        }

        for (zoneName, data) in tokenData {
            do {
                let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
                let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
                zoneChangeTokens[zoneID] = token
            } catch {
                logger.error("Failed to unarchive zone token for \(zoneName): \(error.localizedDescription)")
            }
        }

        logger.info("Loaded zone change tokens for \(zoneChangeTokens.count) zones")
    }

    func scheduleRetryWithExponentialBackoff(operation: String, error: Error) async {
        let currentAttempts = retryAttempts[operation] ?? 0

        guard currentAttempts < Config.maxRetryAttempts else {
            logger.error("Max retry attempts (\(Config.maxRetryAttempts)) exceeded for operation: \(operation)")
            retryAttempts.removeValue(forKey: operation)
            lastRetryTime.removeValue(forKey: operation)
            return
        }

        var delay: TimeInterval = if let ckError = error as? CKError, ckError.isRetryable {
            ckError.retryDelay
        } else {
            5.0
        }

        let backoffMultiplier = pow(2.0, Double(currentAttempts))
        delay = min(delay * backoffMultiplier, 300.0)

        let jitter = Double.random(in: 0 ... 0.2) * delay
        delay += jitter

        retryAttempts[operation] = currentAttempts + 1
        lastRetryTime[operation] = Date()

        logger.info("Scheduling retry #\(currentAttempts + 1) for \(operation) in \(String(format: "%.1f", delay)) seconds")

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard let self else { return }

            switch operation {
            case "uploadPendingChanges":
                Task {
                    do {
                        try await self.uploadPendingChanges()
                        self.retryAttempts.removeValue(forKey: operation)
                        self.lastRetryTime.removeValue(forKey: operation)
                    } catch {
                        await self.scheduleRetryWithExponentialBackoff(operation: operation, error: error)
                    }
                }

            case "performFullSync":
                performFullSync()

            case "downloadAndProcessChanges":
                Task {
                    do {
                        try await self.downloadAndProcessChanges()
                        self.retryAttempts.removeValue(forKey: operation)
                        self.lastRetryTime.removeValue(forKey: operation)
                    } catch {
                        await self.scheduleRetryWithExponentialBackoff(operation: operation, error: error)
                    }
                }

            default:
                logger.warning("Unknown operation for retry: \(operation)")
            }
        }
    }

    func resetRetryTracking(for operation: String) {
        retryAttempts.removeValue(forKey: operation)
        lastRetryTime.removeValue(forKey: operation)
    }

    private func trackRecentUpload(recordId: String) {
        let now = Date()
        recentlyUploadedRecords.insert(recordId)
        uploadTimestamps[recordId] = now

        logger.info("Tracking recent upload: \(recordId)")

        cleanupOldUploadTracking()
    }

    func wasRecentlyUploaded(recordId: String) -> Bool {
        guard let uploadTime = uploadTimestamps[recordId] else { return false }

        let timeSinceUpload = Date().timeIntervalSince(uploadTime)
        let isRecent = timeSinceUpload < recentUploadTimeWindow

        if !isRecent {
            recentlyUploadedRecords.remove(recordId)
            uploadTimestamps.removeValue(forKey: recordId)
        }

        return isRecent
    }

    private func cleanupOldUploadTracking() {
        let now = Date()
        let expiredRecords = uploadTimestamps.compactMap { recordId, timestamp in
            now.timeIntervalSince(timestamp) > recentUploadTimeWindow ? recordId : nil
        }

        for recordId in expiredRecords {
            recentlyUploadedRecords.remove(recordId)
            uploadTimestamps.removeValue(forKey: recordId)
        }

        if !expiredRecords.isEmpty {
            logger.info("Cleaned up \(expiredRecords.count) expired upload tracking entries")
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

private extension CKError {
    var isRetryable: Bool {
        switch code {
        case .serviceUnavailable, .networkFailure, .zoneBusy, .requestRateLimited, .networkUnavailable:
            true
        default:
            false
        }
    }

    var retryDelay: TimeInterval {
        switch code {
        case .networkUnavailable, .networkFailure:
            5.0 // Retry network issues quickly
        case .zoneBusy:
            10.0 // Zone busy needs more time
        case .requestRateLimited:
            30.0 // Rate limited needs longer delay
        case .serviceUnavailable:
            15.0 // Service issues need moderate delay
        default:
            2.0
        }
    }
}
