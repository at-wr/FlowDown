//
//  ConversationSearchController.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//  Implemented by Alan Ye on 7/8/25 with Love :)
//

import AlertController
import SnapKit
import Storage
import UIKit

#if targetEnvironment(macCatalyst)
    class ConversationSearchController: AlertBaseController {
        init(callback: @escaping SearchCallback) {
            super.init(
                rootViewController: NavigationController(callback: callback),
                preferredWidth: 660,
                preferredHeight: 420
            )
            shouldDismissWhenTappedAround = true
            shouldDismissWhenEscapeKeyPressed = true
        }

        override func contentViewDidLoad() {
            super.contentViewDidLoad()
            contentView.backgroundColor = .background
        }

        class NavigationController: UINavigationController {
            init(callback: @escaping SearchCallback) {
                super.init(rootViewController: ContentController(callback: callback))
                navigationBar.isHidden = true
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError()
            }
        }
    }
#else
    class ConversationSearchController: UINavigationController {
        init(callback: @escaping SearchCallback) {
            super.init(rootViewController: ContentController(callback: callback))
            navigationBar.isHidden = true
            modalPresentationStyle = .formSheet
            modalTransitionStyle = .coverVertical
            preferredContentSize = .init(width: 550, height: 550)
            view.backgroundColor = .background
            isModalInPresentation = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }
    }
#endif

extension ConversationSearchController {
    typealias SearchCallback = (Conversation.ID?) -> Void
}

extension ConversationSearchController.ContentController: UITableViewDataSource {
    func numberOfSections(in _: UITableView) -> Int {
        searchResults.isEmpty ? 0 : 1
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath) as? SearchResultCell else {
            assertionFailure("Failed to dequeue SearchResultCell")
            return UITableViewCell()
        }
        let result = searchResults[indexPath.row]
        let searchTerm = searchBar.text ?? ""
        let isHighlighted = highlightedIndex == indexPath.row
        cell.configure(with: result, searchTerm: searchTerm, isHighlighted: isHighlighted)

        // Update currentHighlightedCell reference if this is the highlighted cell
        if isHighlighted {
            currentHighlightedCell = cell
        }

        return cell
    }
}

extension ConversationSearchController.ContentController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        highlightedIndex = indexPath.row
        selectResult(at: indexPath)
    }
}

extension ConversationSearchController.ContentController: UISearchBarDelegate {
    func searchBar(_: UISearchBar, textDidChange searchText: String) {
        searchTimer?.invalidate()
        highlightedIndex = nil
        currentHighlightedCell = nil

        guard !searchText.isEmpty else {
            searchResults = []
            DispatchQueue.main.async { [weak self] in
                guard let self, view.window != nil, tableView.superview != nil else { return }
                tableView.reloadData()
                updateNoResultsView()
                // Clear any stale cell references after reload
                currentHighlightedCell = nil
            }
            return
        }

        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            self?.performSearch(query: searchText)
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        if !searchResults.isEmpty {
            let indexToSelect = highlightedIndex ?? 0
            highlightedIndex = indexToSelect
            handleEnterKey()
        }
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

protocol KeyboardNavigationDelegate: AnyObject {
    func didPressUpArrow()
    func didPressDownArrow()
    func didPressEnter()
}

class KeyboardNavigationSearchBar: UISearchBar {
    weak var keyboardNavigationDelegate: KeyboardNavigationDelegate?

    override func awakeFromNib() {
        super.awakeFromNib()
        setupKeyboardHandling()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupKeyboardHandling()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeyboardHandling()
    }

    private func setupKeyboardHandling() {}

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }

            switch key.keyCode {
            case .keyboardReturnOrEnter:
                keyboardNavigationDelegate?.didPressEnter()
                return
            case .keyboardUpArrow:
                keyboardNavigationDelegate?.didPressUpArrow()
                return
            case .keyboardDownArrow:
                keyboardNavigationDelegate?.didPressDownArrow()
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

extension ConversationSearchController.ContentController: KeyboardNavigationDelegate {
    func didPressUpArrow() {
        handleUpArrow()
    }

    func didPressDownArrow() {
        handleDownArrow()
    }

    func didPressEnter() {
        handleEnterKey()
    }
}

extension ConversationSearchController {
    class ContentController: UIViewController {
        var callback: SearchCallback

        let searchBar = KeyboardNavigationSearchBar()
        let tableView = UITableView(frame: .zero, style: .plain)
        let noResultsView = UIView()
        let emptyStateView = UIView()

        var searchResults: [SearchResult] = []
        private var searchTimer: Timer?
        private var highlightedIndex: Int?
        private weak var currentHighlightedCell: SearchResultCell?
        private var noResultsViewBottomConstraint: Constraint?
        private var emptyStateViewBottomConstraint: Constraint?
        private var tableViewBottomConstraint: Constraint?
        private var hasKeyboard = false

        init(callback: @escaping SearchCallback) {
            self.callback = callback
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            searchTimer?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }

        private func observeKeyboardConnections() {}

        override func viewDidLoad() {
            super.viewDidLoad()

            view.backgroundColor = .background

            searchBar.placeholder = String(localized: "Search")
            searchBar.delegate = self
            searchBar.showsCancelButton = true
            searchBar.searchBarStyle = .minimal
            searchBar.keyboardNavigationDelegate = self

            view.addSubview(searchBar)
            searchBar.snp.makeConstraints { make in
                make.top.equalTo(view.safeAreaLayoutGuide)
                make.left.right.equalToSuperview()
                make.height.equalTo(56)
            }

            tableView.keyboardDismissMode = .none

            view.addSubview(tableView)
            tableView.snp.makeConstraints { make in
                make.top.equalTo(searchBar.snp.bottom)
                make.left.right.equalToSuperview()
                tableViewBottomConstraint = make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).constraint
            }
            tableView.delegate = self
            tableView.dataSource = self
            tableView.register(SearchResultCell.self, forCellReuseIdentifier: "SearchResultCell")
            tableView.backgroundColor = .clear
            tableView.separatorStyle = .singleLine
            tableView.separatorInset = .zero
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = 60

            setupNoResultsView()
            setupEmptyStateView()
            setupKeyboardHandling()
            setupKeyboardNavigation()

            observeKeyboardConnections()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)

            // For touch devices, focus immediately for fast keyboard popup
            #if !targetEnvironment(macCatalyst)
                if traitCollection.userInterfaceIdiom == .phone {
                    searchBar.becomeFirstResponder()
                }
            #endif
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)

            // For devices with external keyboards or iPad, focus after presentation completes
            #if targetEnvironment(macCatalyst)
                DispatchQueue.main.async { [weak self] in
                    guard let self, view.window != nil else { return }
                    searchBar.becomeFirstResponder()
                }
            #else
                if traitCollection.userInterfaceIdiom != .phone {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, view.window != nil else { return }
                        searchBar.becomeFirstResponder()
                    }
                }
            #endif

            DispatchQueue.main.async { [weak self] in
                guard let self, view.window != nil, tableView.superview != nil else { return }
                tableView.reloadData()
                updateNoResultsView()
                // Clear any stale cell references after reload
                currentHighlightedCell = nil
            }
        }

        func performSearch(query: String) {
            searchResults = ConversationManager.shared.searchConversations(query: query)
            highlightedIndex = nil
            currentHighlightedCell = nil

            DispatchQueue.main.async { [weak self] in
                guard let self, view.window != nil, tableView.superview != nil else { return }
                tableView.reloadData()
                updateNoResultsView()
                // Clear any stale cell references after reload
                currentHighlightedCell = nil
            }
        }

        func setupKeyboardNavigation() {
            searchBar.returnKeyType = .search
        }

        private func handleEnterKey() {
            guard !searchResults.isEmpty else { return }

            // If no specific row is highlighted, use the first one
            let indexToSelect = highlightedIndex ?? 0
            guard indexToSelect >= 0, indexToSelect < searchResults.count else { return }

            let indexPath = IndexPath(row: indexToSelect, section: 0)

            // Update highlighted index if needed
            if highlightedIndex != indexToSelect {
                updateHighlightedIndex(indexToSelect)
            }

            // Brief visual feedback, then navigate
            if let cell = tableView.cellForRow(at: indexPath) as? SearchResultCell {
                // Quick scale animation to show selection
                UIView.animate(withDuration: 0.1, animations: {
                    cell.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
                }) { _ in
                    UIView.animate(withDuration: 0.1, animations: {
                        cell.transform = .identity
                    }) { _ in
                        self.selectResult(at: indexPath)
                    }
                }
            } else {
                selectResult(at: indexPath)
            }
        }

        private func handleUpArrow() {
            guard !searchResults.isEmpty else { return }

            if let currentIndex = highlightedIndex {
                let newIndex = max(0, currentIndex - 1)
                updateHighlightedIndex(newIndex)
            } else {
                updateHighlightedIndex(searchResults.count - 1)
            }
        }

        private func handleDownArrow() {
            guard !searchResults.isEmpty else { return }

            if let currentIndex = highlightedIndex {
                let newIndex = min(searchResults.count - 1, currentIndex + 1)
                updateHighlightedIndex(newIndex)
            } else {
                updateHighlightedIndex(0)
            }
        }

        private func updateHighlightedIndex(_ newIndex: Int) {
            highlightedIndex = newIndex

            // Clear all visible cells' highlight state first to prevent double highlighting
            for visibleCell in tableView.visibleCells {
                if let searchCell = visibleCell as? SearchResultCell {
                    searchCell.updateHighlightState(false)
                }
            }
            currentHighlightedCell = nil

            // Update the new highlighted cell
            let newIndexPath = IndexPath(row: newIndex, section: 0)
            if let newCell = tableView.cellForRow(at: newIndexPath) as? SearchResultCell {
                newCell.updateHighlightState(true)
                currentHighlightedCell = newCell
            }

            tableView.scrollToRow(at: newIndexPath, at: .none, animated: true)
        }

        private func selectResult(at indexPath: IndexPath) {
            guard indexPath.row < searchResults.count else { return }

            let result = searchResults[indexPath.row]
            let conversationId = result.conversation.id

            if let navController = navigationController {
                navController.dismiss(animated: true) { [weak self] in
                    self?.callback(conversationId)
                }
            } else {
                dismiss(animated: true) { [weak self] in
                    self?.callback(conversationId)
                }
            }
        }

        func setupNoResultsView() {
            noResultsView.backgroundColor = .clear

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.spacing = 12
            stackView.alignment = .center

            let iconView = UIImageView()
            iconView.image = UIImage(systemName: "moon.zzz")
            iconView.tintColor = .secondaryLabel
            iconView.contentMode = .scaleAspectFit
            iconView.snp.makeConstraints { make in
                make.width.height.equalTo(64)
            }

            let titleLabel = UILabel()
            titleLabel.text = String(localized: "No Results")
            titleLabel.font = .preferredFont(forTextStyle: .headline)
            titleLabel.textColor = .label
            titleLabel.textAlignment = .center

            let subtitleLabel = UILabel()
            subtitleLabel.text = String(localized: "Check the spelling or try a new search.")
            subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
            subtitleLabel.textColor = .secondaryLabel
            subtitleLabel.textAlignment = .center
            subtitleLabel.numberOfLines = 0

            stackView.addArrangedSubview(iconView)
            stackView.addArrangedSubview(titleLabel)
            stackView.addArrangedSubview(subtitleLabel)

            noResultsView.addSubview(stackView)
            stackView.snp.makeConstraints { make in
                make.center.equalToSuperview()
                make.width.lessThanOrEqualTo(300)
            }

            view.addSubview(noResultsView)
            noResultsView.snp.makeConstraints { make in
                make.top.equalTo(searchBar.snp.bottom)
                make.left.right.equalToSuperview()
                noResultsViewBottomConstraint = make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).constraint
            }

            noResultsView.isHidden = true
        }

        func updateNoResultsView() {
            guard view.window != nil, tableView.superview != nil else { return }

            let hasQuery = !(searchBar.text ?? "").isEmpty
            let hasResults = !searchResults.isEmpty

            noResultsView.isHidden = !hasQuery || hasResults
            emptyStateView.isHidden = hasQuery
            tableView.isHidden = hasQuery && !hasResults
        }

        func setupEmptyStateView() {
            emptyStateView.backgroundColor = .clear

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.spacing = 12
            stackView.alignment = .center

            let iconView = UIImageView()
            iconView.image = UIImage(systemName: "loupe")
            iconView.tintColor = .secondaryLabel
            iconView.contentMode = .scaleAspectFit
            iconView.snp.makeConstraints { make in
                make.width.height.equalTo(64)
            }

            let titleLabel = UILabel()
            titleLabel.text = String(localized: "Search Conversations")
            titleLabel.font = .preferredFont(forTextStyle: .headline)
            titleLabel.textColor = .label
            titleLabel.textAlignment = .center

            let subtitleLabel = UILabel()
            subtitleLabel.text = String(localized: "Find conversations by title or message")
            subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
            subtitleLabel.textColor = .secondaryLabel
            subtitleLabel.textAlignment = .center
            subtitleLabel.numberOfLines = 0

            stackView.addArrangedSubview(iconView)
            stackView.addArrangedSubview(titleLabel)
            stackView.addArrangedSubview(subtitleLabel)

            emptyStateView.addSubview(stackView)
            stackView.snp.makeConstraints { make in
                make.center.equalToSuperview()
                make.width.lessThanOrEqualTo(300)
            }

            view.addSubview(emptyStateView)
            emptyStateView.snp.makeConstraints { make in
                make.top.equalTo(searchBar.snp.bottom)
                make.left.right.equalToSuperview()
                emptyStateViewBottomConstraint = make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).constraint
            }
        }

        func setupKeyboardHandling() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillShow(_:)),
                name: UIResponder.keyboardWillShowNotification,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillHide(_:)),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
        }

        @objc func keyboardWillShow(_ notification: NSNotification) {
            guard let userInfo = notification.userInfo,
                  let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            else {
                return
            }

            let keyboard = view.convert(keyboardFrame, from: view.window)
            let height = view.frame.size.height

            if (keyboard.origin.y + keyboard.size.height) > height {
                hasKeyboard = true
            }

            updateLayoutForKeyboard(notification: notification)
        }

        @objc func keyboardWillHide(_ notification: NSNotification) {
            hasKeyboard = false
            updateLayoutForKeyboard(notification: notification)
        }

        @objc func keyboardWillChangeFrame(_ notification: NSNotification) {
            updateLayoutForKeyboard(notification: notification)
        }

        private func updateLayoutForKeyboard(notification: NSNotification) {
            guard let userInfo = notification.userInfo,
                  let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
                  let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
                  let animationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            else {
                return
            }

            let convertedFrame = view.convert(keyboardFrame, from: view.window)
            let intersection = view.bounds.intersection(convertedFrame)
            let keyboardHeight = intersection.height

            tableViewBottomConstraint?.update(offset: -keyboardHeight)
            noResultsViewBottomConstraint?.update(offset: -keyboardHeight)
            emptyStateViewBottomConstraint?.update(offset: -keyboardHeight)

            let animationOptions = UIView.AnimationOptions(rawValue: animationCurve << 16)
            UIView.animate(
                withDuration: max(animationDuration, 0.1),
                delay: 0,
                options: [animationOptions, .beginFromCurrentState],
                animations: {
                    self.view.layoutIfNeeded()
                }
            )
        }
    }
}
