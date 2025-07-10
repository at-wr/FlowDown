//
//  ModelManager+Hub.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import Combine
import CryptoKit
import Digger
import Foundation
import Hub
import Storage

private let api = HubApi()

extension ModelManager {
    class HubDownloadProgress: ObservableObject, Equatable, Hashable {
        @Published var overall: Progress = .init(totalUnitCount: 100)
        @Published var currentFilename: String = .init(localized: "Sending Hello...")
        @Published var error: Error? = nil
        @Published var speed: String = ""
        @Published var cancellable: Bool = false

        var isCancelled: Bool = false {
            didSet {
                assert(isCancelled)
                cancellables.forEach { DiggerManager.shared.cancelTask(for: $0) }
            }
        }

        var progressMap: [String: Progress] = [:] {
            didSet { updateOverallProgress() }
        }

        var cancellables: [URL] = []

        func catchError(_ error: Error) {
            DispatchQueue.main.async { self.error = error }
        }

        func acquiredFileList(_ list: [String]) {
            progressMap.removeAll()
            for file in list {
                let progress = Progress()
                progress.totalUnitCount = 100
                progress.completedUnitCount = 0
                progressMap[file] = progress
            }
        }

        func progressOnFile(_ name: String, progress: Progress) {
            if progress.totalUnitCount <= 0 { return }
            DispatchQueue.main.async {
                self.currentFilename = name
                self.progressMap[name] = progress
            }
        }

        func speedUpdate(speed: Int64) {
            let text = ByteCountFormatter.string(fromByteCount: speed, countStyle: .file)
            DispatchQueue.main.async {
                self.speed = String(format: "%@/s", text)
            }
        }

        func completeFile(_ name: String, size: Int64) {
            let progress = progressMap[name, default: .init()]
            progress.totalUnitCount = size
            progress.completedUnitCount = size
            progressMap[name] = progress
        }

        func finalizeDownload() {
            for (name, progress) in progressMap {
                progress.completedUnitCount = progress.totalUnitCount
                progressMap[name] = progress
            }
        }

        func updateOverallProgress() {
            if progressMap.isEmpty { return }
            let totalCompleted = progressMap.values.reduce(0) { $0 + $1.completedUnitCount }
            let totalUnit = progressMap.values.reduce(0) { $0 + $1.totalUnitCount }
            let newOverall = Progress()
            newOverall.completedUnitCount = totalCompleted
            newOverall.totalUnitCount = totalUnit
            if newOverall.totalUnitCount <= 0 { return }
            DispatchQueue.main.async { self.overall = newOverall }
        }

        func saveCancellableURL(_ url: URL) {
            cancellables.append(url)
        }

        func checkContinue() throws {
            guard isCancelled else { return }
            throw NSError(domain: "Downloader", code: 0, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Operation Cancelled"),
            ])
        }

        func onInterfaceDisappear() {
            cancellables.forEach { DiggerManager.shared.cancelTask(for: $0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isCancelled = true
                self.cancellables.forEach { DiggerManager.shared.cancelTask(for: $0) }
            }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(overall)
            hasher.combine(currentFilename)
            hasher.combine(error?.localizedDescription)
            hasher.combine(speed)
            hasher.combine(cancellable)
        }

        static func == (lhs: ModelManager.HubDownloadProgress, rhs: ModelManager.HubDownloadProgress) -> Bool {
            lhs.hashValue == rhs.hashValue
        }
    }
}

extension ModelManager {
    func checkModelSizeFromHugginFace(identifier: String) async throws -> UInt64 {
        let repo = Hub.Repo(id: identifier, type: .models)
        let filenames = try await api.getFilenames(from: repo, matching: [])
        var totalSize = UInt64(0)
        for filename in filenames where !Task.isCancelled {
            let remoteURL = URL(string: "https://huggingface.co")!
                .appendingPathComponent(repo.id)
                .appendingPathComponent("resolve")
                .appendingPathComponent("main")
                .appendingPathComponent(filename)
            var request = URLRequest(url: remoteURL)
            request.httpMethod = "HEAD"
            let (_, resp) = try await URLSession.shared.data(for: request)
            let size = resp.expectedContentLength
            guard size > 0 else { continue }
            totalSize += UInt64(size)
        }
        return totalSize
    }

    @discardableResult
    func downloadModelFromHuggingFace(
        identifier: String,
        populateProgressTo progress: HubDownloadProgress
    ) async throws -> LocalModel {
        assert(!Thread.isMainThread)

        let repo = Hub.Repo(id: identifier, type: .models)

        // prepare temp directories structure
        let modelTempDir = tempDirForDownloadLocalModel(model_identifier: identifier)
        print("[+] preparing temp directory for \(identifier)...")
        let manifestDir = modelTempDir.appendingPathComponent("manifest")
        let contentDir = modelTempDir.appendingPathComponent("content")
        try? FileManager.default.createDirectory(
            at: manifestDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? FileManager.default.createDirectory(
            at: contentDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        print("[+] downloading manifest for \(identifier)...")

        let filenames = try await api.getFilenames(from: repo, matching: [])
        progress.acquiredFileList(filenames)

        await MainActor.run { progress.cancellable = true }

        for filename in filenames {
            try progress.checkContinue()
            let remoteURL = URL(string: "https://huggingface.co")!
                .appendingPathComponent(repo.id)
                .appendingPathComponent("resolve")
                .appendingPathComponent("main")
                .appendingPathComponent(filename)
            var request = URLRequest(url: remoteURL)
            request.httpMethod = "HEAD"
            progress.progressOnFile(filename, progress: .init(totalUnitCount: 100))
            let (_, resp) = try await URLSession.shared.data(for: request)
            let size = resp.expectedContentLength
            progress.progressOnFile(filename, progress: .init(totalUnitCount: size))
        }

        for filename in filenames {
            try progress.checkContinue()

            let dest = contentDir.appendingPathComponent(filename)
            defer {
                let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                progress.completeFile(filename, size: size)
            }
            if FileManager.default.fileExists(atPath: dest.path) {
                print("[+] skipping \(filename) for \(identifier)")
                continue
            }

            print("[+] downloading \(filename) for \(identifier)")
            let remoteURL = URL(string: "https://huggingface.co")!
                .appendingPathComponent(repo.id)
                .appendingPathComponent("resolve")
                .appendingPathComponent("main")
                .appendingPathComponent(filename)

            var i = 0
            var capturedError: Error?
            while i < 5 {
                try progress.checkContinue()
                var someProgressHasBeenMade = false
                do {
                    let result: URL = try await withUnsafeThrowingContinuation { cont in
                        var isContCalled = false
                        DiggerManager.shared.download(with: remoteURL)
                            .progress {
                                progress.progressOnFile(filename, progress: $0)
                                someProgressHasBeenMade = true
                            }
                            .speed { progress.speedUpdate(speed: $0) }
                            .completion { completion in
                                guard !isContCalled else { return }
                                isContCalled = true
                                switch completion {
                                case let .failure(error): cont.resume(throwing: error)
                                case let .success(url): cont.resume(returning: url)
                                }
                            }
                        progress.saveCancellableURL(remoteURL)
                    }
                    try progress.checkContinue()
                    try? FileManager.default.createDirectory(
                        at: dest.deletingLastPathComponent(),
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    try FileManager.default.moveItem(at: result, to: dest)
                    capturedError = nil
                    break
                } catch {
                    capturedError = error
                    if !someProgressHasBeenMade { i += 1 }
                    sleep(3)
                    continue
                }
            }
            if let error = capturedError {
                progress.catchError(error)
                throw error
            }
        }

        await MainActor.run { progress.cancellable = false }
        try progress.checkContinue()

        print("[+] download completed for \(identifier), finalizing...")

        progress.finalizeDownload()

        var size: UInt64 = 0
        for content in try FileManager.default.contentsOfDirectory(atPath: contentDir.path) {
            let url = contentDir.appendingPathComponent(content)
            try size += (FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        }
        print("[+] total size for \(identifier): \(size)")

        // prepare model/manifest directory
        let model = LocalModel(
            model_identifier: identifier,
            downloaded: .init(),
            size: size,
            capabilities: []
        )
        let manifest = manifestDir
            .appendingPathComponent("info")
            .appendingPathExtension("plist")
        try? FileManager.default.removeItem(at: manifest)
        try encoder.encode(model).write(to: manifest)

        // move both directories to final destination
        let modelDir = dirForLocalModel(identifier: model.id)
        print("[+] moving model \(identifier) to final dest \(modelDir)")
        try? FileManager.default.removeItem(at: modelDir)
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.moveItem(at: contentDir, to: modelDir.appendingPathComponent(contentDir.lastPathComponent))
        try FileManager.default.moveItem(at: manifestDir, to: modelDir.appendingPathComponent(manifestDir.lastPathComponent))

        let models = scanLocalModels()
        localModels.send(models)

        return model
    }
}
