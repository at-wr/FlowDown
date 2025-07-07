//
//  Syncable.swift
//  FlowDown
//
//  Created by Alan Ye on 7/4/25.
//

import Foundation
import MarkdownParser
import Storage
import UIKit

protocol Syncable: Codable, Hashable {
    var cloudId: String { get set }

    static var syncableType: String { get }
    func createPayload(storage: Storage) throws -> Data
}

extension Syncable {
    static var syncableType: String {
        let name = String(describing: self)
        guard let first = name.first else { return "" }
        return first.lowercased() + name.dropFirst()
    }
}

struct ConversationPayload: Codable {
    let cloudId: String
    let title: String
    let creation: Date
    let lastModified: Date
    let icon: Data
    let isFavorite: Bool
    let shouldAutoRename: Bool
    let modelId: String?
}

struct MessagePayload: Codable {
    let cloudId: String
    let conversationCloudId: String
    let creation: Date
    let lastModified: Date
    let role: Message.Role
    let thinkingDuration: TimeInterval
    let reasoningContent: String
    let isThinkingFold: Bool
    let document: String
    let documentNodes: [MarkdownBlockNode]
    let webSearchStatus: Message.WebSearchStatus
    let toolStatus: Message.ToolStatus
}

struct AttachmentPayload: Codable {
    let cloudId: String
    let messageCloudId: String
    let data: Data
    let previewImageData: Data
    let imageRepresentation: Data
    let representedDocument: String
    let type: String
    let name: String
    let storageSuffix: String
    let objectIdentifier: String
}

struct CloudModelPayload: Codable {
    let cloudId: String
    let model_identifier: String
    let model_list_endpoint: String
    let creation: Date
    let lastModified: Date
    let endpoint: String
    let token: String
    let headers: [String: String]
    let capabilities: Set<ModelCapabilities>
    let context: ModelContextLength
    let comment: String
}

extension Conversation: Syncable {
    public func createPayload(storage _: Storage) throws -> Data {
        let maxIconSize = 500_000
        var processedIcon: Data
        if icon.count > maxIconSize {
            if let image = UIImage(data: icon) {
                var compressionQuality: CGFloat = 0.7
                var compressedData = image.jpegData(compressionQuality: compressionQuality) ?? Data()

                while compressedData.count > maxIconSize, compressionQuality > 0.1 {
                    compressionQuality -= 0.1
                    compressedData = image.jpegData(compressionQuality: compressionQuality) ?? Data()
                }

                if compressedData.count <= maxIconSize {
                    processedIcon = compressedData
                } else {
                    processedIcon = createDefaultConversationIconData()
                }
            } else {
                processedIcon = createDefaultConversationIconData()
            }
        } else {
            processedIcon = icon
        }

        let payload = ConversationPayload(
            cloudId: cloudId,
            title: title,
            creation: creation,
            lastModified: lastModified,
            icon: processedIcon,
            isFavorite: isFavorite,
            shouldAutoRename: shouldAutoRename,
            modelId: modelId
        )

        let encodedData = try PropertyListEncoder().encode(payload)

        if encodedData.count > 1_000_000 {
            throw NSError(domain: "CloudKitSync", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Conversation payload too large: \(encodedData.count) bytes",
            ])
        }

        return encodedData
    }

    private func createDefaultConversationIconData() -> Data {
        let defaultIconSize: CGFloat = 40
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: defaultIconSize, height: defaultIconSize))

        let defaultIcon = renderer.image { context in
            UIColor.systemBlue.setFill()
            let rect = CGRect(x: 0, y: 0, width: defaultIconSize, height: defaultIconSize)
            context.cgContext.fillEllipse(in: rect)
        }

        return defaultIcon.pngData() ?? Data()
    }
}

extension Message: Syncable {
    public func createPayload(storage: Storage) throws -> Data {
        guard let conversation = storage.conversationWith(identifier: conversationId), !conversation.cloudId.isEmpty else {
            throw NSError(domain: "CloudKitSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot sync Message(\(id)): its parent Conversation(\(conversationId)) has not been synced yet (missing cloudId)."])
        }

        let maxContentSize = 800_000
        let processedDocument = document.count > maxContentSize ?
            String(document.prefix(maxContentSize)) + "\n\n[Content truncated for sync]" : document
        let processedReasoningContent = reasoningContent.count > maxContentSize ?
            String(reasoningContent.prefix(maxContentSize)) + "\n\n[Content truncated for sync]" : reasoningContent

        let payload = MessagePayload(
            cloudId: cloudId,
            conversationCloudId: conversation.cloudId,
            creation: creation,
            lastModified: lastModified,
            role: role,
            thinkingDuration: thinkingDuration,
            reasoningContent: processedReasoningContent,
            isThinkingFold: isThinkingFold,
            document: processedDocument,
            documentNodes: documentNodes,
            webSearchStatus: webSearchStatus,
            toolStatus: toolStatus
        )

        let encodedData = try PropertyListEncoder().encode(payload)

        if encodedData.count > 1_000_000 {
            throw NSError(domain: "CloudKitSync", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Message payload too large: \(encodedData.count) bytes",
            ])
        }

        return encodedData
    }
}

extension Attachment: Syncable {
    public func createPayload(storage: Storage) throws -> Data {
        guard let message = storage.listMessages().first(where: { $0.id == self.messageId }), !message.cloudId.isEmpty else {
            throw NSError(domain: "CloudKitSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot sync Attachment(\(id)): its parent Message(\(messageId)) has not been synced yet (missing cloudId)."])
        }

        let maxDataSize = 200_000
        let maxTextSize = 50000

        let processedData = data.count > maxDataSize ? Data() : data
        let processedPreviewImageData = previewImageData.count > maxDataSize ? Data() : previewImageData
        let processedImageRepresentation = imageRepresentation.count > maxDataSize ? Data() : imageRepresentation
        let processedRepresentedDocument = representedDocument.count > maxTextSize ?
            String(representedDocument.prefix(maxTextSize)) + "\n\n[Content truncated]" : representedDocument

        let payload = AttachmentPayload(
            cloudId: cloudId,
            messageCloudId: message.cloudId,
            data: processedData,
            previewImageData: processedPreviewImageData,
            imageRepresentation: processedImageRepresentation,
            representedDocument: processedRepresentedDocument,
            type: type,
            name: name,
            storageSuffix: storageSuffix,
            objectIdentifier: objectIdentifier
        )

        let encodedData = try PropertyListEncoder().encode(payload)

        if encodedData.count > 1_000_000 {
            let minimalPayload = AttachmentPayload(
                cloudId: cloudId,
                messageCloudId: message.cloudId,
                data: Data(),
                previewImageData: Data(),
                imageRepresentation: Data(),
                representedDocument: "[Attachment too large for sync]",
                type: type,
                name: name,
                storageSuffix: storageSuffix,
                objectIdentifier: objectIdentifier
            )
            return try PropertyListEncoder().encode(minimalPayload)
        }

        return encodedData
    }
}

extension CloudModel: Syncable {
    public var cloudId: String {
        get { id }
        set { id = newValue }
    }

    public func createPayload(storage _: Storage) throws -> Data {
        let payload = CloudModelPayload(
            cloudId: id,
            model_identifier: model_identifier,
            model_list_endpoint: model_list_endpoint,
            creation: creation,
            lastModified: lastModified,
            endpoint: endpoint,
            token: token,
            headers: headers,
            capabilities: capabilities,
            context: context,
            comment: comment
        )

        let encodedData = try PropertyListEncoder().encode(payload)

        if encodedData.count > 1_000_000 {
            throw NSError(domain: "CloudKitSync", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "CloudModel payload too large: \(encodedData.count) bytes",
            ])
        }

        return encodedData
    }
}
