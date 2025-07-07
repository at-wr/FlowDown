//
//  CKSyncManager+Background.swift
//  FlowDown
//
//  Created by Alan Ye on 7/5/25.
//

import BackgroundTasks
import CloudKit
import Combine
import Foundation
import OSLog

// MARK: - Background Processing

extension CloudKitSyncManager {
    /// Sets up background task registration and processing
    func setupBackgroundTasks() {
        // Register background task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Config.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundSync(task as! BGProcessingTask)
        }

        // Schedule initial background task
        scheduleBackgroundSync()
    }

    /// Handles background sync execution
    private func handleBackgroundSync(_ task: BGProcessingTask) {
        logger.info("Starting background sync task")

        backgroundTask = task

        // Set expiration handler
        task.expirationHandler = {
            self.logger.warning("Background sync task expired")
            self.backgroundTask?.setTaskCompleted(success: false)
            self.backgroundTask = nil
        }

        // Perform background sync
        Task {
            do {
                try await self.performBackgroundSync()
                self.backgroundTask?.setTaskCompleted(success: true)
            } catch {
                self.logger.error("Background sync failed: \(error.localizedDescription)")
                self.backgroundTask?.setTaskCompleted(success: false)
            }

            self.backgroundTask = nil

            // Schedule next background task
            self.scheduleBackgroundSync()
        }
    }

    /// Performs optimized background sync
    private func performBackgroundSync() async throws {
        logger.info("Performing background sync")

        do {
            // Only upload pending changes in background to preserve battery
            try await uploadPendingChanges()

            // Perform lightweight data fetch if conditions are right
            if shouldPerformBackgroundDownload() {
                try await downloadRemoteChanges()
            }

            // Cleanup old deferred records
            await cleanupDeferredRecords()

            logger.info("Background sync completed successfully")

        } catch {
            logger.error("Background sync error: \(error.localizedDescription)")
        }
    }

    /// Determines if background download should be performed
    private func shouldPerformBackgroundDownload() -> Bool {
        // Only download in background if:
        // 1. Last sync was more than 1 hour ago
        // 2. Device is on WiFi and charging (when available)
        // 3. No recent user activity

        guard let lastSync = lastSyncDate else { return true }

        let hoursSinceLastSync = Date().timeIntervalSince(lastSync) / 3600
        return hoursSinceLastSync > 1.0
    }

    /// Schedules the next background sync
    private func scheduleBackgroundSync() {
        let request = BGProcessingTaskRequest(identifier: Config.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false // Allow on battery for user data
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes from now

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled next background sync")
        } catch {
            logger.error("Failed to schedule background sync: \(error.localizedDescription)")
        }
    }

    /// Cleans up old deferred records that are unlikely to be resolved
    private func cleanupDeferredRecords() async {
        let cutoffDate = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago
        let oldRecords = storage.deferredRecordList().filter { $0.lastAttempt < cutoffDate }

        for record in oldRecords {
            storage.deferredRecordDequeue(record.recordName)
        }

        if !oldRecords.isEmpty {
            logger.info("Cleaned up \(oldRecords.count) old deferred records")
        }
    }
}

// MARK: - Auto Sync Setup

extension CloudKitSyncManager {
    /// Sets up automatic sync triggers
    func setupAutoSync() {
        // Sync when app becomes active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppBecameActive()
            }
            .store(in: &cancellables)

        // Sync when entering background (for upload)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleAppEnteredBackground()
            }
            .store(in: &cancellables)

        // Monitor network connectivity
        setupNetworkMonitoring()
    }

    /// Handles app becoming active
    private func handleAppBecameActive() {
        logger.info("App became active, checking if sync needed")

        // Sync if it's been a while or this is first time setup
        if isFirstTimeSetup {
            Task {
                try? await performFirstTimeSetup()
            }
        } else if shouldSyncOnAppActivation() {
            performFullSync()
        }
    }

    /// Handles app entering background
    private func handleAppEnteredBackground() {
        logger.info("App entered background, uploading pending changes")

        // Upload any pending changes before going to background
        Task {
            try? await uploadPendingChanges()
        }
    }

    /// Determines if sync should be performed when app becomes active
    private func shouldSyncOnAppActivation() -> Bool {
        guard let lastSync = lastSyncDate else { return true }

        // Sync if last sync was more than 1 minute ago to ensure data freshness
        let minutesSinceLastSync = Date().timeIntervalSince(lastSync) / 60
        return minutesSinceLastSync > 1
    }

    /// Sets up network connectivity monitoring
    private func setupNetworkMonitoring() {
        // Monitor network changes to trigger sync when connectivity is restored
        // This would typically use Network framework, but for simplicity we'll use a timer

        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkAndSyncIfNeeded()
            }
            .store(in: &cancellables)
    }

    /// Periodically checks if sync is needed
    private func checkAndSyncIfNeeded() {
        // Don't sync if already syncing
        guard syncStatus == .idle || syncStatus == .completed else { return }

        // Check if there are pending uploads that need to be sent
        let pendingCount = storage.pendingUploadCount()
        if pendingCount > 0 {
            logger.info("Found \(pendingCount) pending uploads, triggering sync")
            performFullSync()
        }
    }
}
