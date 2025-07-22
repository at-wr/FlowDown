//
//  NSAttributedString+Search.swift
//  FlowDown
//
//  Created by Alan Ye on 7/8/25.
//

import UIKit

extension NSAttributedString {
    static func highlightedString(
        text: String,
        searchTerm: String,
        baseAttributes: [NSAttributedString.Key: Any] = [:],
        highlightAttributes: [NSAttributedString.Key: Any] = [:]
    ) -> NSAttributedString {
        guard !searchTerm.isEmpty else {
            return NSAttributedString(string: text, attributes: baseAttributes)
        }
        let attributedString = NSMutableAttributedString(string: text, attributes: baseAttributes)

        let lowercasedText = text.lowercased()
        let lowercasedSearchTerm = searchTerm.lowercased()

        var searchRange = lowercasedText.startIndex ..< lowercasedText.endIndex
        while let range = lowercasedText.range(of: lowercasedSearchTerm, options: [], range: searchRange) {
            let nsRange = NSRange(range, in: text)
            attributedString.addAttributes(highlightAttributes, range: nsRange)

            searchRange = range.upperBound ..< lowercasedText.endIndex
        }

        return attributedString
    }
}
