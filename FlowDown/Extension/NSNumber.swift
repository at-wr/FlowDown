//
//  NSNumber.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/10/25.
//

import Foundation

extension NSNumber {
    var isBool: Bool {
        CFBooleanGetTypeID() == CFGetTypeID(self)
    }

    var isInteger: Bool {
        !isBool && floor(doubleValue) == doubleValue
    }
}
