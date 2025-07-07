//
//  Attachment.swift
//  Objects
//
//  Created by 秋星桥 on 1/23/25.
//

import Foundation
import WCDBSwift

public final class Attachment: Identifiable, Codable, TableCodable {
    public var id: Int64 = .init()
    public var cloudId: String = .init()
    public var messageId: Message.ID = .init()
    public var data: Data = .init()
    public var previewImageData: Data = .init()
    public var imageRepresentation: Data = .init()
    public var representedDocument: String = ""
    public var type: String = ""
    public var name: String = ""
    public var storageSuffix: String = ""
    /// Records the UUID used when the object was created, for identification during modifications.
    public var objectIdentifier: String = .init()

    public init() {}

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = Attachment
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isAutoIncrement: true, isUnique: true)
            BindColumnConstraint(cloudId, isNotNull: true, isUnique: true, defaultTo: "")
            BindColumnConstraint(messageId, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(data, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(previewImageData, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(representedDocument, isNotNull: true, defaultTo: "")
            BindColumnConstraint(type, isNotNull: true, defaultTo: "")
            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(storageSuffix, isNotNull: true, defaultTo: "")
            BindColumnConstraint(imageRepresentation, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(objectIdentifier, isNotNull: true, defaultTo: "")

            BindForeginKey(
                messageId,
                foreignKey: ForeignKey()
                    .references(with: Message.table)
                    .columns(Message.CodingKeys.id)
                    .onDelete(.cascade)
            )
        }

        case id
        case cloudId
        case messageId
        case data
        case previewImageData
        case imageRepresentation
        case representedDocument
        case type
        case name
        case storageSuffix
        case objectIdentifier
    }

    public var isAutoIncrement: Bool = false // 用于定义是否使用自增的方式插入
    public var lastInsertedRowID: Int64 = 0 // 用于获取自增插入后的主键值
}

extension Attachment: Equatable {
    public static func == (lhs: Attachment, rhs: Attachment) -> Bool {
        lhs.id == rhs.id &&
            lhs.cloudId == rhs.cloudId &&
            lhs.messageId == rhs.messageId &&
            lhs.data == rhs.data &&
            lhs.previewImageData == rhs.previewImageData &&
            lhs.imageRepresentation == rhs.imageRepresentation &&
            lhs.representedDocument == rhs.representedDocument &&
            lhs.type == rhs.type &&
            lhs.name == rhs.name &&
            lhs.storageSuffix == rhs.storageSuffix &&
            lhs.objectIdentifier == rhs.objectIdentifier
    }
}

extension Attachment: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(cloudId)
        hasher.combine(messageId)
        hasher.combine(data)
        hasher.combine(previewImageData)
        hasher.combine(imageRepresentation)
        hasher.combine(representedDocument)
        hasher.combine(type)
        hasher.combine(name)
        hasher.combine(storageSuffix)
        hasher.combine(objectIdentifier)
    }
}
