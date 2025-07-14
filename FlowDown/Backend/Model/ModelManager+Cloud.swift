//
//  ModelManager+Cloud.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/28/25.
//

import CommonCrypto
import Foundation
import Storage

extension CloudModel {
    var modelDisplayName: String {
        var ret = model_identifier
        let scope = scopeIdentifier
        if !scope.isEmpty, ret.hasPrefix(scopeIdentifier + "/") {
            ret.removeFirst(scopeIdentifier.count + 1)
        }
        if ret.isEmpty { ret = String(localized: "Not Configured") }
        return ret
    }

    var modelFullName: String {
        let host = URL(string: endpoint)?.host
        return [
            model_identifier,
            host,
        ].compactMap(\.self).joined(separator: "@")
    }

    var scopeIdentifier: String {
        if model_identifier.contains("/") {
            return model_identifier.components(separatedBy: "/").first ?? ""
        }
        return ""
    }

    var inferenceHost: String { URL(string: endpoint)?.host ?? "" }

    var auxiliaryIdentifier: String {
        [
            "@",
            inferenceHost,
            scopeIdentifier.isEmpty ? "" : "@\(scopeIdentifier)",
        ].filter { !$0.isEmpty }.joined()
    }

    var tags: [String] {
        var input: [String] = []
        input.append(auxiliaryIdentifier)
        let caps = ModelCapabilities.allCases.filter { capabilities.contains($0) }.map(\.title)
        input.append(contentsOf: caps)
        return input.filter { !$0.isEmpty }
    }
}

extension ModelManager {
    func scanCloudModels() -> [CloudModel] {
        let models: [CloudModel] = sdb.cloudModelList()
        for model in models where model.id.isEmpty {
            // Ensure all models have a valid ID
            model.id = UUID().uuidString
            sdb.cloudModelRemove(identifier: "")
            sdb.cloudModelEdit(identifier: model.id) { $0.id = model.id }
            return scanCloudModels()
        }
        return models
    }

    func refreshCloudModels() {
        let models = scanCloudModels()
        cloudModels.send(models)
        print("[+] refreshed \(models.count) cloud models")
    }

    func newCloudModel() -> CloudModel {
        let object = CloudModel()
        sdb.cloudModelPut(object)
        CloudKitSyncManager.shared.syncLocalChange(for: object, changeType: .create)
        defer { cloudModels.send(scanCloudModels()) }

        // Trigger immediate sync for better responsiveness
        Task {
            CloudKitSyncManager.shared.performFullSync()
        }

        return object
    }

    func newCloudModel(profile: CloudModel) -> CloudModel {
        // Only assign a new UUID if the profile doesn't already have one
        // This preserves deterministic UUIDs for builtin models
        if profile.id.isEmpty {
            profile.id = UUID().uuidString
        }
        sdb.cloudModelPut(profile)
        CloudKitSyncManager.shared.syncLocalChange(for: profile, changeType: .create)
        defer { cloudModels.send(scanCloudModels()) }
        return profile
    }

    func insertCloudModel(_ model: CloudModel) {
        sdb.cloudModelPut(model)
        CloudKitSyncManager.shared.syncLocalChange(for: model, changeType: .create)
        cloudModels.send(scanCloudModels())

        // Trigger immediate sync for cloud model import
        Task {
            CloudKitSyncManager.shared.performFullSync()
        }
    }

    func cloudModel(identifier: CloudModelIdentifier?) -> CloudModel? {
        guard let identifier else { return nil }
        return sdb.cloudModel(with: identifier)
    }

    func removeCloudModel(identifier: CloudModelIdentifier) {
        if let model = cloudModel(identifier: identifier) {
            CloudKitSyncManager.shared.syncLocalChange(for: model, changeType: .delete)
        }
        sdb.cloudModelRemove(identifier: identifier)
        cloudModels.send(scanCloudModels())
    }

    func editCloudModel(identifier: CloudModelIdentifier?, block: @escaping (inout CloudModel) -> Void) {
        guard let identifier else { return }
        sdb.cloudModelEdit(identifier: identifier, block)
        if let model = sdb.cloudModel(with: identifier) {
            // Use forced sync for configuration changes to bypass debouncing
            CloudKitSyncManager.shared.forceSyncLocalChange(for: model, changeType: .update)
        }
        cloudModels.send(scanCloudModels())
    }

    func fetchModelList(identifier: CloudModelIdentifier?, block: @escaping ([String]) -> Void) {
        guard let model = cloudModel(identifier: identifier) else {
            block([])
            return
        }
        let endpoint = model.endpoint
        var model_list_endpoint = model.model_list_endpoint
        if model_list_endpoint.contains("$INFERENCE_ENDPOINT$") {
            if model.endpoint.isEmpty {
                block([])
                return
            }
            model_list_endpoint = model_list_endpoint.replacingOccurrences(of: "$INFERENCE_ENDPOINT$", with: endpoint)
        }
        guard !model_list_endpoint.isEmpty, let url = URL(string: model_list_endpoint)?.standardized else {
            block([])
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        if !model.token.isEmpty { request.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization") }
        for (key, value) in model.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let dic = try? JSONSerialization.jsonObject(with: data, options: [])
            else { return block([]) }
            let value = self.scrubModel(fromDic: dic).sorted()
            block(value)
        }.resume()
    }

    private func scrubModel(fromDic dic: Any) -> [String] {
        if let dic = dic as? [String: Any],
           let data = dic["data"] as? [[String: Any]]
        {
            data.compactMap { $0["id"] as? String }
        } else if let data = dic as? [[String: Any]] {
            data.compactMap { $0["id"] as? String }
        } else {
            []
        }
    }

    func importCloudModel(at url: URL) throws -> CloudModel {
        let decoder = PropertyListDecoder()
        let data = try Data(contentsOf: url)
        let model = try decoder.decode(CloudModel.self, from: data)
        if model.id.isEmpty { model.id = UUID().uuidString }
        insertCloudModel(model)
        return model
    }
}
