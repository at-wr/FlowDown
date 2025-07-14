//
//  Storage+ModelContextClient.swift
//  Storage
//
//  Created by LiBr on 6/29/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func modelContextServerList() -> [ModelContextServer] {
        (
            try? db.getObjects(
                fromTable: ModelContextServer.table,
                orderBy: [
                    ModelContextServer.Properties.id.order(.ascending),
                ]
            )
        ) ?? []
    }

    func modelContextServerMake() -> ModelContextServer {
        let object = ModelContextServer()
        try? db.insert([object], intoTable: ModelContextServer.table)
        return object
    }

    func modelContextServerPut(object: ModelContextServer) {
        try? db.insertOrReplace(
            [object],
            intoTable: ModelContextServer.table
        )
    }

    func modelContextServerWith(_ identifier: ModelContextServer.ID) -> ModelContextServer? {
        try? db.getObject(
            fromTable: ModelContextServer.table,
            where: ModelContextServer.Properties.id == identifier
        )
    }

    func modelContextServerEdit(identifier: ModelContextServer.ID, _ block: @escaping (inout ModelContextServer) -> Void) {
        let read: ModelContextServer? = try? db.getObject(
            fromTable: ModelContextServer.table,
            where: ModelContextServer.Properties.id == identifier
        )
        guard var object = read else { return }
        block(&object)
        try? db.insertOrReplace(
            [object],
            intoTable: ModelContextServer.table
        )
    }

    func modelContextServerRemove(identifier: ModelContextServer.ID) {
        try? db.delete(
            fromTable: ModelContextServer.table,
            where: ModelContextServer.Properties.id == identifier
        )
    }
}
