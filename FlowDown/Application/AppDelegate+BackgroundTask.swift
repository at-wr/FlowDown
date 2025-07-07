//
//  AppDelegate+BackgroundTask.swift
//  FlowDown
//
//  Created by Alan Ye on 7/4/25.
//

import BackgroundTasks
import OSLog
import UIKit

extension AppDelegate {
    private static let backgroundTaskIdentifier = "wiki.qaq.flowdown.compaction"
    private var logger: Logger { Logger(subsystem: "wiki.qaq.flowdown.appdelegate", category: "BackgroundTask") }

    /// Registers the background task for CloudKit compaction with the system.
    /// This should be called from `application(_:didFinishLaunchingWithOptions:)`.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier, using: nil) { task in
            self.logger.info("Background compaction task started.")

            // Reschedule for the next time.
            self.scheduleCompactionTask()

            // Handle expiration: The system is about to terminate the app.
            task.expirationHandler = {
                self.logger.warning("Background compaction task expired. System is terminating the task.")
                // In a real-world scenario with long-running operations, you would cancel them here.
            }

            // --- Perform the Compaction ---
            // Kick off the asynchronous compaction process using the new sync manager.
            Task {
                await CloudKitSyncManager.shared.performCompaction()
            }
            // -----------------------------

            task.setTaskCompleted(success: true)
            self.logger.info("Background task handler finished, async compaction work continues.")
        }
        logger.info("Successfully registered background task for CloudKit compaction.")
    }

    /// Schedules the CloudKit compaction background task to run when the system deems it appropriate.
    /// This can be called when the app enters the background.
    func scheduleCompactionTask() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)

        // This task requires the device to be connected to a network.
        request.requiresNetworkConnectivity = true
        // This task is best performed when the device is idle and charging.
        request.requiresExternalPower = true

        // Setting an earliest begin date. The system will not run the task before this time.
        // A common pattern is to schedule it for some time in the future, e.g., 12-24 hours,
        // to avoid running it too frequently.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60) // 12 hours from now

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Successfully scheduled CloudKit compaction background task.")
        } catch {
            // This can fail for various reasons, e.g., if the identifier is not registered
            // in the Info.plist under "Permitted background task scheduler identifiers".
            logger.error("Could not schedule CloudKit compaction task: \(error.localizedDescription)")
        }
    }
}
