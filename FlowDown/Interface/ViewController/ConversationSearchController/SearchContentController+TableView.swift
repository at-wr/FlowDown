//
//  SearchContentController+TableView.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/9/25.
//

import UIKit

extension SearchContentController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        highlightedIndex = indexPath
        selectResultAndDismiss(at: indexPath)
    }
}

extension SearchContentController: UITableViewDataSource {
    func numberOfSections(in _: UITableView) -> Int {
        1 // always be 1
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath) as? SearchResultCell else {
            assertionFailure()
            return UITableViewCell()
        }
        let result = searchResults[indexPath.row]
        let searchTerm = searchBar.text ?? ""
        let isHighlighted = highlightedIndex == indexPath
        cell.configure(with: result, searchTerm: searchTerm, isHighlighted: isHighlighted)
        return cell
    }
}
