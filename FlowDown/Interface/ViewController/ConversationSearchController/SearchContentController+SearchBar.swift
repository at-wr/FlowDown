//
//  SearchContentController+SearchBar.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/9/25.
//

import UIKit

extension SearchContentController: UISearchBarDelegate {
    func searchBar(_: UISearchBar, textDidChange searchText: String) {
        highlightedIndex = nil

        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(performSearch(query:)),
            object: nil
        )
        perform(#selector(performSearch(query:)), with: searchText, afterDelay: 0.1)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        guard !searchResults.isEmpty else { return }

        let indexToSelect = highlightedIndex?.row ?? 0
        highlightedIndex = .init(row: indexToSelect, section: 0)
        handleEnterKey()
    }

    func searchBarCancelButtonClicked(_: UISearchBar) {
        if let navController = navigationController {
            navController.dismiss(animated: true) { [weak self] in
                self?.callback(nil)
            }
        } else {
            dismiss(animated: true) { [weak self] in
                self?.callback(nil)
            }
        }
    }
}
