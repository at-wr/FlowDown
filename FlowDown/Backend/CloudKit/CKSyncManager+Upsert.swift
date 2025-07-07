//
//  CKSyncManager+Upsert.swift
//  FlowDown
//
//  Created by Alan Ye on 7/5/25.
//

import CloudKit
import Foundation
import OSLog
import Storage

extension CloudKitSyncManager {
    func upsertConversation(from payload: ConversationPayload, version: Date, deviceId: String?) async throws {
        if let localConversation = storage.findConversation(byCloudId: payload.cloudId) {
            if shouldUpdateLocalObject(localVersion: localConversation.lastModified, remoteVersion: version, remoteDeviceId: deviceId) {
                logger.info("Remote version is newer, updating conversation \(payload.cloudId)")
            } else {
                logger.info("Local version is newer or equal, skipping update for conversation \(payload.cloudId)")
                return
            }

            localConversation.title = payload.title.isEmpty ? "Untitled Conversation" : payload.title
            localConversation.creation = payload.creation
            localConversation.lastModified = version

            if !payload.icon.isEmpty {
                localConversation.icon = payload.icon
            } else if localConversation.icon.isEmpty {
                localConversation.icon = createDefaultConversationIcon()
            }

            localConversation.isFavorite = payload.isFavorite
            localConversation.shouldAutoRename = payload.shouldAutoRename
            localConversation.modelId = payload.modelId

            storage.conversationUpdate(object: localConversation)
            logger.info("Updated conversation: \(payload.cloudId), title: '\(localConversation.title)', icon size: \(localConversation.icon.count) bytes")
        } else {
            logger.info("Creating new conversation from remote: \(payload.cloudId) with title: '\(payload.title)'")

            let newConversation = storage.conversationMake()

            newConversation.cloudId = payload.cloudId
            newConversation.title = payload.title.isEmpty ? "Untitled Conversation" : payload.title
            newConversation.creation = payload.creation
            newConversation.lastModified = version

            if !payload.icon.isEmpty {
                newConversation.icon = payload.icon
            } else {
                newConversation.icon = createDefaultConversationIcon()
            }

            newConversation.isFavorite = payload.isFavorite
            newConversation.shouldAutoRename = payload.shouldAutoRename
            newConversation.modelId = payload.modelId

            storage.conversationUpdate(object: newConversation)

            logger.info("Created conversation with local ID: \(newConversation.id), title: '\(newConversation.title)', icon size: \(newConversation.icon.count) bytes")
        }

        await notifyUIOfDataChange(type: .conversation, operation: .upsert)

        Task { @MainActor in
            let conversationListNeedsRefresh = await checkIfConversationListNeedsRefresh(cloudId: payload.cloudId)

            if conversationListNeedsRefresh {
                ConversationManager.shared.scanAll()

                NotificationCenter.default.post(
                    name: NSNotification.Name("ConversationListDidChange"),
                    object: payload.cloudId
                )
            }

            if let conversation = storage.findConversation(byCloudId: payload.cloudId) {
                let session = ConversationSessionManager.shared.session(for: conversation.id)
                if session.isActive {
                    session.refreshContentsFromDatabase()
                    session.notifyMessagesDidChange()
                }
            }
        }

        logger.info("Successfully upserted conversation: \(payload.cloudId)")
    }

    private func createDefaultConversationIcon() -> Data {
        let defaultIconSize: CGFloat = 40
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: defaultIconSize, height: defaultIconSize))

        let defaultIcon = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: defaultIconSize, height: defaultIconSize))
        }

        return defaultIcon.pngData() ?? Data()
    }

    private func checkIfConversationListNeedsRefresh(cloudId: String) async -> Bool {
        let existingConversation = storage.findConversation(byCloudId: cloudId)
        return existingConversation?.id == nil || ConversationManager.shared.isConversationListVisible
    }

    func upsertMessage(from payload: MessagePayload, version: Date, deviceId: String?) async throws {
        guard let parentConversation = storage.findConversation(byCloudId: payload.conversationCloudId) else {
            throw ProcessingError.dependencyMissing("Message \(payload.cloudId) requires parent conversation \(payload.conversationCloudId)")
        }

        if let localMessage = storage.findMessage(byCloudId: payload.cloudId) {
            if shouldUpdateLocalObject(localVersion: localMessage.lastModified, remoteVersion: version, remoteDeviceId: deviceId) {
                logger.info("Remote version is newer, updating message \(payload.cloudId)")
            } else {
                logger.info("Local version is newer or equal, skipping update for message \(payload.cloudId)")
                return
            }

            localMessage.conversationId = parentConversation.id
            localMessage.creation = payload.creation
            localMessage.lastModified = version
            localMessage.role = payload.role
            localMessage.thinkingDuration = payload.thinkingDuration
            localMessage.reasoningContent = payload.reasoningContent
            localMessage.isThinkingFold = payload.isThinkingFold
            localMessage.document = payload.document
            localMessage.documentNodes = payload.documentNodes
            localMessage.webSearchStatus = payload.webSearchStatus
            localMessage.toolStatus = payload.toolStatus

            storage.insertOrReplace(object: localMessage)
        } else {
            logger.info("Creating new message from remote: \(payload.cloudId)")

            let newMessage = storage.makeMessage(with: parentConversation.id)

            newMessage.cloudId = payload.cloudId
            newMessage.creation = payload.creation
            newMessage.lastModified = version
            newMessage.role = payload.role
            newMessage.thinkingDuration = payload.thinkingDuration
            newMessage.reasoningContent = payload.reasoningContent
            newMessage.isThinkingFold = payload.isThinkingFold
            newMessage.document = payload.document
            newMessage.documentNodes = payload.documentNodes
            newMessage.webSearchStatus = payload.webSearchStatus
            newMessage.toolStatus = payload.toolStatus

            storage.insertOrReplace(object: newMessage)

            logger.info("Created message with ID: \(newMessage.id) for conversation: \(parentConversation.id)")
        }

        await notifyUIOfDataChange(type: .message, operation: .upsert)

        await MainActor.run {
            ConversationManager.shared.scanAll()

            let session = ConversationSessionManager.shared.session(for: parentConversation.id)
            session.refreshContentsFromDatabase()
            session.notifyMessagesDidChange()

            let messagesInConversation = storage.listMessages(within: parentConversation.id)
            logger.info("Conversation \(parentConversation.id) now has \(messagesInConversation.count) messages after upsert")

            NotificationCenter.default.post(
                name: NSNotification.Name("ConversationDataChanged"),
                object: parentConversation.id
            )
        }

        logger.info("Successfully upserted message: \(payload.cloudId)")
    }

    func upsertAttachment(from payload: AttachmentPayload, version _: Date, deviceId _: String?) async throws {
        guard let parentMessage = storage.findMessage(byCloudId: payload.messageCloudId) else {
            throw ProcessingError.dependencyMissing("Attachment \(payload.cloudId) requires parent message \(payload.messageCloudId)")
        }

        if let existing = storage.findAttachment(byCloudId: payload.cloudId) {
            logger.info("Updating attachment \(payload.cloudId)")

            existing.messageId = parentMessage.id
            existing.data = payload.data
            existing.previewImageData = payload.previewImageData
            existing.imageRepresentation = payload.imageRepresentation
            existing.representedDocument = payload.representedDocument
            existing.type = payload.type
            existing.name = payload.name
            existing.storageSuffix = payload.storageSuffix
            existing.objectIdentifier = payload.objectIdentifier

            storage.attachmentsUpdate([existing])
        } else {
            logger.info("Creating new attachment from remote: \(payload.cloudId)")

            let localAttachment = storage.attachmentMake(with: parentMessage.id)

            localAttachment.cloudId = payload.cloudId
            localAttachment.data = payload.data
            localAttachment.previewImageData = payload.previewImageData
            localAttachment.imageRepresentation = payload.imageRepresentation
            localAttachment.representedDocument = payload.representedDocument
            localAttachment.type = payload.type
            localAttachment.name = payload.name
            localAttachment.storageSuffix = payload.storageSuffix
            localAttachment.objectIdentifier = payload.objectIdentifier

            storage.attachmentsUpdate([localAttachment])
        }

        await notifyUIOfDataChange(type: .attachment, operation: .upsert)

        logger.info("Successfully upserted attachment: \(payload.cloudId)")
    }

    func upsertCloudModel(from payload: CloudModelPayload, version: Date, deviceId: String?) async throws {
        if let localModel = storage.cloudModel(with: payload.cloudId) {
            if shouldUpdateLocalObject(localVersion: localModel.lastModified, remoteVersion: version, remoteDeviceId: deviceId) {
                logger.info("Remote version is newer, updating cloud model \(payload.cloudId)")
            } else {
                logger.info("Local version is newer or equal, skipping update for cloud model \(payload.cloudId)")
                return
            }

            localModel.model_identifier = payload.model_identifier
            localModel.model_list_endpoint = payload.model_list_endpoint
            localModel.creation = payload.creation
            localModel.lastModified = version
            localModel.endpoint = payload.endpoint
            localModel.token = payload.token
            localModel.capabilities = payload.capabilities
            localModel.context = payload.context
            localModel.headers = payload.headers
            localModel.comment = payload.comment

            logger.info("Updated CloudModel: \(payload.cloudId), capabilities: \(payload.capabilities.count), context: \(payload.context.rawValue), headers: \(payload.headers.count)")

            storage.cloudModelPut(localModel)
        } else {
            logger.info("Creating new cloud model from remote: \(payload.cloudId)")
            let newModel = CloudModel()

            newModel.id = payload.cloudId
            newModel.model_identifier = payload.model_identifier
            newModel.model_list_endpoint = payload.model_list_endpoint
            newModel.creation = payload.creation
            newModel.lastModified = version
            newModel.endpoint = payload.endpoint
            newModel.token = payload.token
            newModel.headers = payload.headers
            newModel.capabilities = payload.capabilities
            newModel.context = payload.context
            newModel.comment = payload.comment

            storage.cloudModelPut(newModel)
        }

        await notifyUIOfDataChange(type: .cloudModel, operation: .upsert)

        await MainActor.run {
            ModelManager.shared.refreshCloudModels()
        }

        logger.info("Successfully upserted cloud model: \(payload.cloudId)")
    }

    private func shouldUpdateLocalObject(localVersion: Date, remoteVersion: Date, remoteDeviceId: String?) -> Bool {
        let timeDifference = remoteVersion.timeIntervalSince(localVersion)

        let shouldUpdate: Bool

        if let remoteDeviceId {
            if remoteDeviceId == deviceId {
                logger.warning("Received record from same device in conflict resolution - this should have been filtered earlier")
                shouldUpdate = false
            } else if abs(timeDifference) < 5.0 {
                shouldUpdate = remoteDeviceId < deviceId
                logger.info("Close timestamps (\(timeDifference)s) with device ID (\(remoteDeviceId)), using device ID comparison. Local device: \(deviceId), accepting remote: \(shouldUpdate)")
            } else if timeDifference > 0 {
                shouldUpdate = true
                logger.info("Remote version from device \(remoteDeviceId) is newer by \(timeDifference)s, accepting update")
            } else if timeDifference < -300.0 {
                shouldUpdate = false
                logger.info("Local version is much newer by \(abs(timeDifference))s, rejecting remote update from device \(remoteDeviceId)")
            } else {
                shouldUpdate = true
                logger.info("Local version newer by \(abs(timeDifference))s, but accepting remote from device \(remoteDeviceId) to ensure sync consistency")
            }
        } else {
            if abs(timeDifference) < 2.0 {
                shouldUpdate = true
                logger.info("Close timestamps (\(timeDifference)s), no device ID, accepting remote for sync consistency")
            } else if timeDifference > 0 {
                shouldUpdate = true
                logger.info("Remote version is newer by \(timeDifference)s, accepting update")
            } else if timeDifference < -300.0 {
                shouldUpdate = false
                logger.info("Local version is much newer by \(abs(timeDifference))s, rejecting remote update")
            } else {
                shouldUpdate = true
                logger.info("Local version slightly newer by \(abs(timeDifference))s, but accepting remote (possible clock drift)")
            }
        }

        logger.info("Version comparison - Local: \(localVersion), Remote: \(remoteVersion), Difference: \(timeDifference)s, Should update: \(shouldUpdate)")

        return shouldUpdate
    }

    private func notifyUIOfDataChange(type: DataChangeType, operation: DataOperation) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .dataDidChange,
                object: nil,
                userInfo: [
                    "type": type,
                    "operation": operation,
                ]
            )
        }
    }
}

enum DataChangeType {
    case conversation
    case message
    case attachment
    case cloudModel
}

enum DataOperation {
    case upsert
    case delete
}

extension Notification.Name {
    static let dataDidChange = Notification.Name("DataDidChange")
}

extension CloudKitSyncManager {
    private func resolveConflict<T: Syncable>(
        local: T,
        remote: T,
        remoteVersion _: Date
    ) -> ConflictResolution<T> {
        if local.cloudId.isEmpty {
            return .useRemote(remote)
        }

        return .useRemote(remote)
    }
}

enum ConflictResolution<T> {
    case useLocal(T)
    case useRemote(T)
    case merge(T)
    case requireUserIntervention(T, T)
}
