//
//  Ext+TableCodable.swift
//  Objects
//
//  Created by 秋星桥 on 1/23/25.
//

import Foundation
import WCDBSwift

public extension TableEncodable {
    static var table: String { String(describing: self) }
}
