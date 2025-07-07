//
//  AppDelegate+CloudKit.swift
//  FlowDown
//
//  Created by Alan Ye on 7/4/25.
//

import CloudKit
import UIKit
import UserNotifications

extension AppDelegate {
    func setupCloudKit() {
        let syncManager = CloudKitSyncManager.shared

        /// Init
        Task {
            do {
                if syncManager.isFirstTimeSetup {
                    try await syncManager.performFirstTimeSetup()
                } else {
                    syncManager.performFullSync()
                }
            } catch {
                print("CloudKit setup failed: \(error.localizedDescription)")
            }
        }

        registerForRemoteNotifications()
    }

    /// Setup APNs
    private func registerForRemoteNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Error requesting notification authorization: \(error.localizedDescription)")
                return
            }
            guard granted else {
                print("Notification authorization denied.")
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Remote Notification Delegate

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Successfully registered for remote notifications with device token: \(token)")
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    /// Trigger sync on incoming remote notifications
    func application(_: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("Received remote notification.")

        let timeoutWorkItem = DispatchWorkItem {
            print("Remote notification handler timed out.")
            completionHandler(.failed)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeoutWorkItem)

        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            Task {
                let result = await CloudKitSyncManager.shared.handleCloudKitNotification(notification)
                timeoutWorkItem.cancel()

                switch result {
                case .newData:
                    print("CloudKit sync completed with new data.")
                    completionHandler(.newData)
                case .noData:
                    print("CloudKit sync completed with no new data.")
                    completionHandler(.noData)
                case .failed:
                    print("CloudKit sync failed.")
                    completionHandler(.failed)
                @unknown default:
                    print("Unknown background fetch result.")
                    completionHandler(.noData)
                }
            }
        } else {
            // if not CloudKit related
            timeoutWorkItem.cancel()
            completionHandler(.noData)
        }
    }
}
