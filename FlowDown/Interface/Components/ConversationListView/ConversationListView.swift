//
//  ConversationListView.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/3/25.
//

import ChidoriMenu
import Combine
import Foundation
import Storage
import UIKit

private class GroundedTableView: UITableView {
    @objc var allowsHeaderViewsToFloat: Bool { false }
    @objc var allowsFooterViewsToFloat: Bool { false }
}

class ConversationListView: UIView {
    let tableView: UITableView
    let dataSource: DataSource

    var cancellables: Set<AnyCancellable> = []

    typealias DataIdentifier = Conversation.ID
    typealias SectionIdentifier = Date

    typealias DataSource = UITableViewDiffableDataSource<SectionIdentifier, DataIdentifier>
    typealias Snapshot = NSDiffableDataSourceSnapshot<SectionIdentifier, DataIdentifier>

    let selection = CurrentValueSubject<Conversation.ID?, Never>(nil)

    weak var delegate: Delegate? {
        didSet { delegate?.conversationListView(didSelect: selection.value) }
    }

    var keepMyFocusTimer: Timer? = nil

    init() {
        tableView = GroundedTableView(frame: .zero, style: .plain)
        tableView.register(Cell.self, forCellReuseIdentifier: "Cell")

        dataSource = .init(tableView: tableView) { tableView, indexPath, itemIdentifier in
            tableView.separatorColor = .clear
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! Cell
            let conv = ConversationManager.shared.conversation(identifier: itemIdentifier)
            cell.use(conv)
            return cell
        }
        dataSource.defaultRowAnimation = .fade

        super.init(frame: .zero)

        isUserInteractionEnabled = true

        addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.separatorInset = .zero
        tableView.separatorColor = .clear
        tableView.contentInset = .zero
        tableView.allowsMultipleSelection = false
        tableView.selectionFollowsFocus = true
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionHeaderHeight = UITableView.automaticDimension

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl

        selection
            .ensureMainThread()
            .sink { [weak self] identifier in
                guard let self else { return }
                var selectedIndexPath = Set(tableView.indexPathsForSelectedRows ?? [])
                if let identifier,
                   let indexPath = dataSource.indexPath(for: identifier)
                {
                    let visible = tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
                    tableView.selectRow(
                        at: indexPath,
                        animated: false,
                        scrollPosition: visible ? .none : .middle
                    )
                    selectedIndexPath.remove(indexPath)
                }
                for index in selectedIndexPath {
                    tableView.deselectRow(at: index, animated: false)
                }
            }
            .store(in: &cancellables)

        selection
            .removeDuplicates()
            .ensureMainThread()
            .sink { [weak self] identifier in
                guard let self else { return }
                delegate?.conversationListView(didSelect: identifier)
            }
            .store(in: &cancellables)

        ConversationManager.shared.conversations
            .ensureMainThread()
            .sink { [weak self] _ in
                self?.updateDataSource()
            }
            .store(in: &cancellables)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            keepAtLeastOncFocus()
        }
        RunLoop.main.add(timer, forMode: .common)
        keepMyFocusTimer = timer
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        keepMyFocusTimer?.invalidate()
        keepMyFocusTimer = nil
    }

    func updateDataSource() {
        let list = ConversationManager.shared.conversations.value.values
        guard !list.isEmpty else {
            _ = ConversationManager.shared.initialConversation()
            return
        }

        var snapshot = Snapshot()

        let favorited = list.filter(\.isFavorite)
        if !favorited.isEmpty {
            let favoriteSection = Date(timeIntervalSince1970: -1)
            snapshot.appendSections([favoriteSection])
            snapshot.appendItems(favorited.map(\.id), toSection: favoriteSection)
        }

        let calendar = Calendar.current

        var conversationsByDate: [Date: [Conversation.ID]] = [:]
        for item in list where !item.isFavorite {
            let dateOnly = calendar.startOfDay(for: item.creation)
            if conversationsByDate[dateOnly] == nil {
                conversationsByDate[dateOnly] = []
            }
            conversationsByDate[dateOnly]?.append(item.id)
        }

        let sortedDates = conversationsByDate.keys.sorted(by: >)

        for date in sortedDates {
            snapshot.appendSections([date])
            if let conversations = conversationsByDate[date] {
                snapshot.appendItems(conversations, toSection: date)
            }
        }
        let previousSections = dataSource.snapshot().sectionIdentifiers
        if previousSections.count == 1, sortedDates.count > 1 {
            // reload all!
            snapshot.reloadSections(sortedDates)
        }

        dataSource.apply(snapshot, animatingDifferences: true)

        DispatchQueue.main.async { [self] in
            var snapshot = dataSource.snapshot()
            let visibleRows = tableView.indexPathsForVisibleRows ?? []
            let visibleItemIdentifiers = visibleRows
                .map { dataSource.itemIdentifier(for: $0) }
                .compactMap(\.self)
            snapshot.reconfigureItems(visibleItemIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: true)
            keepAtLeastOncFocus()
        }
    }

    func select(identifier: Conversation.ID) {
        selection.send(identifier)

        DispatchQueue.main.async {
            var snapshot = self.dataSource.snapshot()

            // Safety check: only reconfigure if the item exists in the snapshot
            if snapshot.itemIdentifiers.contains(identifier) {
                snapshot.reconfigureItems([identifier])
                self.dataSource.apply(snapshot, animatingDifferences: true)
            } else {
                print("[+] Warning: Attempted to select conversation \(identifier) that doesn't exist in snapshot yet")
                // Schedule a retry after a short delay to allow data source to update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    var retrySnapshot = self.dataSource.snapshot()
                    if retrySnapshot.itemIdentifiers.contains(identifier) {
                        retrySnapshot.reconfigureItems([identifier])
                        self.dataSource.apply(retrySnapshot, animatingDifferences: true)
                    }
                }
            }
        }
    }

    func keepAtLeastOncFocus() {
        guard tableView.indexPathsForSelectedRows?.count ?? 0 == 0 else { return }
        let item = ConversationManager.shared.conversations.value.values.first
        if let item {
            // Only select if the item exists in the current snapshot
            let snapshot = dataSource.snapshot()
            if snapshot.itemIdentifiers.contains(item.id) {
                select(identifier: item.id)
            }
        } else {
            selection.send(nil)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // detect command + 1/2/3/4 ... 9 to select conversation
        var resolved = false
        for press in presses {
            guard let key = press.key else { continue }
            let keyCode = key.charactersIgnoringModifiers
            guard keyCode.count == 1,
                  key.modifierFlags.contains(.command),
                  var digit = Int(keyCode)
            else { continue }
            digit -= 1
            guard digit >= 0, digit < dataSource.snapshot().numberOfItems else {
                continue
            }

            // now check which section we are in
            let snapshot = dataSource.snapshot()
            var sectionIndex: Int? = nil
            var sectionItemIndex: Int? = nil
            var currentCount = 0
            for (index, section) in snapshot.sectionIdentifiers.enumerated() {
                let count = snapshot.numberOfItems(inSection: section)
                if currentCount + count > digit {
                    sectionIndex = index
                    sectionItemIndex = digit - currentCount
                    break
                }
                currentCount += count
            }
            guard let sectionIndex, let sectionItemIndex else {
                assertionFailure()
                continue
            }
            let indexPath = IndexPath(item: sectionItemIndex, section: sectionIndex)
            let identifier = dataSource.itemIdentifier(for: indexPath)
            selection.send(identifier)
            resolved = true
        }
        if !resolved {
            super.pressesBegan(presses, with: event)
        }
    }

    @objc private func handlePullToRefresh(_: UIRefreshControl) {
        print("[+] Pull-to-refresh triggered")

        // Check if sync is already in progress
        let syncManager = CloudKitSyncManager.shared
        let currentStatus = syncManager.syncStatus
        let canStartSync = switch currentStatus {
        case .idle, .completed, .failed:
            true
        default:
            false
        }

        print("[+] Current sync status: \(currentStatus), can start sync: \(canStartSync)")

        guard canStartSync else {
            // Sync already in progress, end refresh immediately
            print("[+] Sync already in progress, ending refresh")
            DispatchQueue.main.async { [weak self] in
                self?.tableView.refreshControl?.endRefreshing()
            }
            return
        }

        // Set up observers for sync completion
        var syncCompletionObserver: NSObjectProtocol?
        var syncFailureObserver: NSObjectProtocol?
        var timeoutWorkItem: DispatchWorkItem?

        let endRefresh = { [weak self] in
            print("[+] Ending pull-to-refresh")
            DispatchQueue.main.async {
                self?.tableView.refreshControl?.endRefreshing()
                if let observer = syncCompletionObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                if let observer = syncFailureObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                timeoutWorkItem?.cancel()
            }
        }

        // Listen for sync completion
        syncCompletionObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitSyncCompleted,
            object: nil,
            queue: .main
        ) { _ in
            print("[+] Received CloudKit sync completed notification")
            endRefresh()
        }

        // Listen for sync failure
        syncFailureObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloudKitSyncFailed"),
            object: nil,
            queue: .main
        ) { _ in
            print("[+] Received CloudKit sync failed notification")
            endRefresh()
        }

        // Trigger CloudKit sync on pull-to-refresh
        print("[+] Starting CloudKit sync from pull-to-refresh")
        syncManager.performFullSync()

        // Monitor sync status changes in addition to notifications
        var statusObserver: AnyCancellable?
        statusObserver = syncManager.$syncStatus
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch status {
                case .completed, .failed:
                    print("[+] Sync status changed to: \(status)")
                    statusObserver?.cancel()
                    endRefresh()
                default:
                    break
                }
            }

        // Fallback timeout in case notifications don't fire
        timeoutWorkItem = DispatchWorkItem {
            print("[+] Pull-to-refresh timeout reached, ending refresh")
            statusObserver?.cancel()
            endRefresh()
        }

        if let timeoutWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeoutWorkItem)
        }
    }
}
