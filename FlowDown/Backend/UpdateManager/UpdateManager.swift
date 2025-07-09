import AlertController
import DpkgVersion
import Foundation
import UIKit

private enum DistributionChannel: String, Equatable, Hashable {
    case fromApple
    case fromGitHub
}

class UpdateManager: NSObject {
    static let shared = UpdateManager()

    private let currentChannel: DistributionChannel
    private weak var anchorView: UIView?

    override private init() {
        #if targetEnvironment(macCatalyst)
            if let receiptUrl = Bundle.main.appStoreReceiptURL,
               FileManager.default.fileExists(atPath: receiptUrl.path)
            {
                currentChannel = .fromApple
            } else {
                currentChannel = .fromGitHub
            }
        #else
            currentChannel = .fromApple // it's impossible to distribute iOS/iPadOS app through GitHub (right?)
        #endif
        print("[+] UpdateManager initialized with channel: \(currentChannel)")
        super.init()
    }

    private var bundleVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version).\(build)"
    }

    func anchor(_ view: UIView) {
        anchorView = view
    }

    func performUpdateCheckFromUI() {
        guard let controller = anchorView?.parentViewController else {
            print("[!] no anchor view set for UpdateManager.")
            return
        }
        print("[+] checking for updates from \(bundleVersion)...")
        guard [.fromGitHub].contains(currentChannel) else {
            print("[!] Update check is not supported for the current distribution channel.")
            return
        }

        func completion(package: DistributionChannel.RemotePackage?) {
            DispatchQueue.main.async {
                if let package {
                    self.presentUpdateAlert(controller: controller, package: package)
                } else {
                    Indicator.present(
                        title: String(localized: "No Update Available"),
                        preset: .done,
                        haptic: .success,
                        referencingView: controller.view
                    )
                }
            }
        }

        Indicator.progress(
            title: String(localized: "Checking for Updates"),
            controller: controller
        ) { completionHandler in
            Task.detached {
                var package: DistributionChannel.RemotePackage?
                do {
                    let packages = try await self.currentChannel.getRemoteVersion()
                    package = self.newestPackage(from: packages)
                    package = self.updatePackage(from: package)
                    print("[+] remote packages: \(packages)")
                } catch {
                    print("[!] failed to check for updates: \(error.localizedDescription)")
                }
                completionHandler {
                    completion(package: package)
                }
            }
        }
    }

    private func updatePackage(from remotePackage: DistributionChannel.RemotePackage?) -> DistributionChannel.RemotePackage? {
        guard let remotePackage else { return nil }
        let compare = Version.compare(remotePackage.tag, bundleVersion)
        print("[*] comparing \(remotePackage.tag) and \(bundleVersion) result \(compare)")
        guard compare > 0 else { return nil }
        return remotePackage
    }

    private func newestPackage(from list: [DistributionChannel.RemotePackage]) -> DistributionChannel.RemotePackage? {
        guard !list.isEmpty, var find = list.first else { return nil }
        for i in 1 ..< list.count where Version.compare(find.tag, list[i].tag) < 0 {
            find = list[i]
        }
        return find
    }

    private func presentUpdateAlert(controller: UIViewController, package: DistributionChannel.RemotePackage) {
        let alert = AlertViewController(
            title: String(localized: "Update Available"),
            message: String(localized: "A new version \(package.tag) is available. Would you like to download it?"),
        ) { context in
            context.addAction(title: String(localized: "Cancel")) {
                context.dispose()
            }
            context.addAction(title: String(localized: "Download"), attribute: .dangerous) {
                context.dispose {
                    UIApplication.shared.open(package.downloadURL, options: [:])
                }
            }
        }
        controller.present(alert, animated: true)
    }
}

extension DistributionChannel {
    enum UpdateCheckError: Error, LocalizedError {
        case invalidResponse
    }

    struct RemotePackage {
        let tag: String
        let downloadURL: URL
    }

    func getRemoteVersion() async throws -> [RemotePackage] {
        switch self {
        case .fromApple:
            return []
        case .fromGitHub:
            let url = URL(string: "https://api.github.com/repos/Lakr233/FlowDown/releases/latest")!
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  json["body"] as? String != nil, // maybe display updatelog.
                  let htmlUrl = json["html_url"] as? String,
                  let draft = json["draft"] as? Bool,
                  let prerelease = json["prerelease"] as? Bool,
                  !draft,
                  !prerelease,
                  let downloadPageUrl = URL(string: htmlUrl)
            else {
                throw NSError(domain: "UpdateManagerError", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Failed to parse release information.")])
            }
            print("[+] latest release version: \(tagName), url: \(htmlUrl)")
            return [.init(tag: tagName, downloadURL: downloadPageUrl)]
        }
    }
}
