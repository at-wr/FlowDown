//
//  ModelController.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/24/25.
//

import Combine
import ConfigurableKit
import Storage
import UIKit

extension SettingController.SettingContent {
    class ModelController: UIViewController {
        let tableView: UITableView
        let dataSource: DataSource

        enum ModelType: String {
            case local
            case cloud

            var title: String {
                switch self {
                case .local: String(localized: "Local Model")
                case .cloud: String(localized: "Cloud Model")
                }
            }
        }

        struct ModelViewModel: Hashable {
            let type: ModelType
            let identifier: String
        }

        typealias DataSource = UITableViewDiffableDataSource<ModelType, ModelViewModel>
        typealias Snapshot = NSDiffableDataSourceSnapshot<ModelType, ModelViewModel>

        var cancellable: Set<AnyCancellable> = []

        @BareCodableStorage(key: "ModelController.showCloudModel", defaultValue: true)
        var showCloudModels { didSet { updateDataSource() }}

        @BareCodableStorage(key: "ModelController.showLocalModel", defaultValue: true)
        var showLocalModels { didSet { updateDataSource() }}

        init() {
            tableView = UITableView(frame: .zero, style: .plain)
            dataSource = .init(tableView: tableView) { tableView, indexPath, itemIdentifier in
                let cell = tableView.dequeueReusableCell(withIdentifier: "ModelCell", for: indexPath) as! ModelCell
                switch itemIdentifier.type {
                case .local:
                    if let model = ModelManager.shared.localModel(identifier: itemIdentifier.identifier) {
                        let name = model.modelDisplayName
                        let tags = model.tags
                        cell.update(type: .local, name: name, descriptions: tags)
                    }
                case .cloud:
                    if let model = ModelManager.shared.cloudModel(identifier: itemIdentifier.identifier) {
                        let name = model.modelDisplayName
                        let tags = model.tags
                        cell.update(type: .cloud, name: name, descriptions: tags)
                    }
                }
                return cell
            }
            tableView.register(ModelCell.self, forCellReuseIdentifier: "ModelCell")

            super.init(nibName: nil, bundle: nil)
            title = String(localized: "Model Management")

            Publishers.CombineLatest(
                ModelManager.shared.localModels.removeDuplicates(),
                ModelManager.shared.cloudModels.removeDuplicates()
            )
            .ensureMainThread()
            .sink { [weak self] _ in self?.updateDataSource() }
            .store(in: &cancellable)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        deinit {
            cancellable.forEach { $0.cancel() }
            cancellable.removeAll()
        }

        lazy var addItem: UIBarButtonItem = .init(
            image: .init(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addModelBarItemTapped)
        )

        lazy var filterBarItem: UIBarButtonItem = .init(
            image: .init(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(filterBarItemTapped)
        )

        var searchKey: String { navigationItem.searchController?.searchBar.text ?? "" }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background
            tableView.separatorStyle = .singleLine
            tableView.separatorInset = .zero
            tableView.backgroundColor = .clear
            tableView.delegate = self
            tableView.allowsMultipleSelection = false
            tableView.dragDelegate = self
            tableView.dragInteractionEnabled = true
            dataSource.defaultRowAnimation = .fade
            view.addSubview(tableView)
            tableView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }

            navigationItem.rightBarButtonItems = [
                addItem,
                filterBarItem,
            ]

            let searchController = UISearchController(searchResultsController: nil)
            searchController.delegate = self
            searchController.searchBar.placeholder = String(localized: "Search Model")
            searchController.searchBar.autocapitalizationType = .none
            searchController.searchBar.autocorrectionType = .no
            searchController.searchBar.delegate = self
            navigationItem.searchController = searchController
            navigationItem.preferredSearchBarPlacement = .stacked
            navigationItem.hidesSearchBarWhenScrolling = false
            navigationItem.searchController?.obscuresBackgroundDuringPresentation = false
            navigationItem.searchController?.hidesNavigationBarDuringPresentation = false
        }

        func updateDataSource() {
            var snapshot = Snapshot()
            let localModels = ModelManager.shared.localModels.value.filter {
                searchKey.isEmpty || $0.model_identifier.localizedCaseInsensitiveContains(searchKey)
            }
            let remoteModels = ModelManager.shared.cloudModels.value.filter {
                searchKey.isEmpty || $0.model_identifier.localizedCaseInsensitiveContains(searchKey)
            }

            // Get sets of model identifiers to detect duplicates
            let localModelIdentifiers = Set(localModels.map(\.model_identifier))
            let remoteModelIdentifiers = Set(remoteModels.map(\.model_identifier))

            let deduplicatedRemoteModels = remoteModels

            if !localModels.isEmpty, showLocalModels {
                snapshot.appendSections([.local])
                snapshot.appendItems(localModels.map { ModelViewModel(type: .local, identifier: $0.id) }, toSection: .local)
            }
            if !deduplicatedRemoteModels.isEmpty, showCloudModels {
                snapshot.appendSections([.cloud])
                snapshot.appendItems(deduplicatedRemoteModels.map { ModelViewModel(type: .cloud, identifier: $0.id) }, toSection: .cloud)
            }
            dataSource.apply(snapshot, animatingDifferences: true)
            updateVisibleItems()
            updateFilterIcon()
        }

        func updateVisibleItems() {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(tableView.indexPathsForVisibleRows?.compactMap {
                dataSource.itemIdentifier(for: $0)
            } ?? [])
            dataSource.apply(snapshot, animatingDifferences: true)
        }

        func updateFilterIcon() {
            if showCloudModels, showLocalModels {
                filterBarItem.image = .init(systemName: "line.3.horizontal.decrease.circle")
            } else {
                filterBarItem.image = .init(systemName: "line.3.horizontal.decrease.circle.fill")
            }
        }
    }
}
