//
//  Storage+CloudModel.swift
//  Storage
//
//  Created by 秋星桥 on 1/28/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func cloudModelList() -> [CloudModel] {
        (
            try? db.getObjects(
                fromTable: CloudModel.table,
                orderBy: [
                    CloudModel.Properties.model_identifier
                        .order(.ascending),
                ]
            )
        ) ?? []
    }

    func cloudModelPut(_ object: CloudModel) {
        try? db.insertOrReplace(
            [object],
            intoTable: CloudModel.table
        )
    }

    func cloudModel(with identifier: CloudModel.ID) -> CloudModel? {
        try? db.getObject(
            fromTable: CloudModel.table,
            where: CloudModel.Properties.id == identifier
        )
    }

    func cloudModelEdit(identifier: CloudModel.ID, _ block: @escaping (inout CloudModel) -> Void) {
        let read: CloudModel? = try? db.getObject(
            fromTable: CloudModel.table,
            where: CloudModel.Properties.id == identifier
        )
        guard var object = read else { return }
        block(&object)
        object.lastModified = Date()
        try? db.insertOrReplace(
            [object],
            intoTable: CloudModel.table
        )
    }

    func cloudModelRemove(identifier: CloudModel.ID) {
        try? db.delete(
            fromTable: CloudModel.table,
            where: CloudModel.Properties.id == identifier
        )
    }
}
