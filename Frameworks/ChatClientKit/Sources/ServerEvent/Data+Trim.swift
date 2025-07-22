//
//  Data+Trim.swift
//  EventSource
//
//  Created by Firdavs Khaydarov on 06/07/2025.
//

import Foundation

package extension Data {
    func trimmingPrefix(while predicate: (Element) -> Bool) -> SubSequence {
        let start = endOfPrefix(while: predicate)
        return self[start ..< endIndex]
    }

    func trimmingSuffix(while predicate: (Element) -> Bool) -> SubSequence {
        let end = startOfSuffix(while: predicate)
        return self[startIndex ..< end]
    }

    func trimming(while predicate: (Element) -> Bool) -> SubSequence {
        trimmingPrefix(while: predicate).trimmingSuffix(while: predicate)
    }

    func endOfPrefix(while predicate: (Element) -> Bool) -> Index {
        var index = startIndex
        while index != endIndex, predicate(self[index]) {
            formIndex(after: &index)
        }
        return index
    }

    func startOfSuffix(while predicate: (Element) -> Bool) -> Index {
        var index = endIndex
        while index != startIndex {
            let after = index
            formIndex(before: &index)
            if !predicate(self[index]) {
                return after
            }
        }
        return index
    }
}
