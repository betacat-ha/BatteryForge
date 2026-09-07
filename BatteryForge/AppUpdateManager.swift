import AppKit
import Combine
import Foundation

enum AppUpdateChannel: String, CaseIterable, Identifiable {
    case release
    case beta
    case alpha

    static let storageKey = "app.updateChannel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .release: AppLanguage.localized("app_update.channel.release")
        case .beta: AppLanguage.localized("app_update.channel.beta")
        case .alpha: AppLanguage.localized("app_update.channel.alpha")
        }
    }

    var detail: String {
        switch self {
        case .release: AppLanguage.localized("app_update.channel.release.detail")
        case .beta: AppLanguage.localized("app_update.channel.beta.detail")
        case .alpha: AppLanguage.localized("app_update.channel.alpha.detail")
        }
    }

    fileprivate func includes(_ candidate: AppUpdateChannel) -> Bool {
        switch self {
        case .release: candidate == .release
        case .beta: candidate != .alpha
        case .alpha: true
        }
    }
}

@MainActor
final class AppUpdateManager: ObservableObject {
    struct Release: Equatable {
        let version: String
        let name: String
        let pageURL: URL
        let downloadURL: URL?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(Release)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var isUpdateAlertPresented = false
    @Published var channel: AppUpdateChannel {
        didSet {
            UserDefaults.standard.set(channel.rawValue, forKey: AppUpdateChannel.storageKey)
            guard channel != oldValue else { return }
            state = .idle
            hasCheckedAutomatically = false
        }
    }

    let currentVersion: String
    private let currentBuild: Int
    private let installedChannel: AppUpdateChannel

    private let releasesURL = URL(
        string: "https://api.github.com/repos/betacat-ha/BatteryForge/releases?per_page=100"
    )!
    private var hasCheckedAutomatically = false

    init(bundle: Bundle = .main) {
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        currentBuild = Int(build) ?? 0
        let installedChannelValue = bundle.url(forResource: "ReleaseChannel", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        installedChannel = installedChannelValue.flatMap(AppUpdateChannel.init(rawValue:)) ?? .release
        let savedChannel = UserDefaults.standard.string(forKey: AppUpdateChannel.storageKey)
        channel = savedChannel.flatMap(AppUpdateChannel.init(rawValue:)) ?? .release
    }

    func checkAutomaticallyIfNeeded() async {
        guard !hasCheckedAutomatically else { return }
        hasCheckedAutomatically = true
        await checkForUpdates(presentUpToDate: false, presentErrors: false)
    }

    func checkForUpdates(presentUpToDate: Bool = true, presentErrors: Bool = true) async {
        guard state != .checking else { return }
        state = .checking

        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("BatteryForge/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else { throw UpdateError.invalidResponse }

            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            let candidates = releases.compactMap { payload -> ReleaseCandidate? in
                guard !payload.draft,
                      let version = SemanticVersion(payload.tagName),
                      channel.includes(version.channel)
                else { return nil }
                return ReleaseCandidate(payload: payload, version: version)
            }
            guard let candidate = candidates.max(by: { $0.version < $1.version }) else {
                state = .upToDate
                if presentUpToDate { isUpdateAlertPresented = true }
                return
            }
            let payload = candidate.payload
            guard let pageURL = URL(string: payload.htmlURL),
                  let installedVersion = SemanticVersion(
                    currentVersion,
                    channel: installedChannel,
                    sequence: currentBuild
                  )
            else { throw UpdateError.invalidRelease }

            if candidate.version > installedVersion {
                let release = Release(
                    version: payload.tagName.droppingLeadingV,
                    name: payload.name ?? payload.tagName,
                    pageURL: pageURL,
                    downloadURL: payload.assets
                        .first(where: { $0.name.localizedCaseInsensitiveContains("macOS.zip") })
                        .flatMap { URL(string: $0.downloadURL) }
                )
                state = .updateAvailable(release)
                isUpdateAlertPresented = true
            } else {
                state = .upToDate
                if presentUpToDate { isUpdateAlertPresented = true }
            }
        } catch {
            state = .failed(error.localizedDescription)
            if presentErrors { isUpdateAlertPresented = true }
        }
    }

    func openUpdate() {
        guard case .updateAvailable(let release) = state else { return }
        NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
    }

    var statusText: String {
        switch state {
        case .idle:
            return String.localizedStringWithFormat(
                AppLanguage.localized("app_update.status.ready"),
                channel.title
            )
        case .checking:
            return AppLanguage.localized("app_update.status.checking")
        case .upToDate:
            return AppLanguage.localized("app_update.status.up_to_date")
        case .updateAvailable(let release):
            return String.localizedStringWithFormat(
                AppLanguage.localized("app_update.status.available"),
                release.version
            )
        case .failed(let message):
            return String.localizedStringWithFormat(
                AppLanguage.localized("app_update.status.failed"),
                message
            )
        }
    }

    var alertTitle: String {
        switch state {
        case .updateAvailable:
            AppLanguage.localized("app_update.alert.available.title")
        case .upToDate:
            AppLanguage.localized("app_update.alert.up_to_date.title")
        case .failed:
            AppLanguage.localized("app_update.alert.failed.title")
        default:
            AppLanguage.localized("app_update.check")
        }
    }

    var alertMessage: String {
        switch state {
        case .updateAvailable(let release):
            return String.localizedStringWithFormat(
                AppLanguage.localized("app_update.alert.available.message"),
                release.name,
                currentVersion
            )
        case .upToDate:
            return String.localizedStringWithFormat(
                AppLanguage.localized("app_update.alert.up_to_date.message"),
                currentVersion
            )
        case .failed(let message):
            return String.localizedStringWithFormat(
                AppLanguage.localized("app_update.alert.failed.message"),
                message
            )
        default:
            return ""
        }
    }
}

private extension AppUpdateManager {
    struct ReleaseCandidate {
        let payload: GitHubRelease
        let version: SemanticVersion
    }

    struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let downloadURL: String

            private enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let name: String?
        let htmlURL: String
        let assets: [Asset]
        let draft: Bool
        let prerelease: Bool

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case assets
            case draft, prerelease
        }
    }

    struct SemanticVersion: Comparable {
        let components: [Int]
        let channel: AppUpdateChannel
        let sequence: Int

        init?(_ rawValue: String) {
            let parts = rawValue.droppingLeadingV.split(separator: "-", maxSplits: 1)
            guard let value = parts.first else { return nil }
            let versionComponents = value.split(separator: ".")
            let components = versionComponents.compactMap { Int($0) }
            guard components.count == versionComponents.count,
                  !components.isEmpty
            else { return nil }
            self.components = components
            if parts.count == 1 {
                channel = .release
                sequence = 0
            } else {
                let prereleaseParts = parts[1].split(separator: ".", maxSplits: 1)
                guard let channelName = prereleaseParts.first,
                      let parsedChannel = AppUpdateChannel(rawValue: String(channelName)),
                      parsedChannel != .release
                else { return nil }
                channel = parsedChannel
                sequence = prereleaseParts.count == 2 ? Int(prereleaseParts[1]) ?? 0 : 0
            }
        }

        init?(_ rawValue: String, channel: AppUpdateChannel, sequence: Int) {
            guard let parsed = SemanticVersion(rawValue) else { return nil }
            components = parsed.components
            self.channel = channel
            self.sequence = channel == .release ? 0 : sequence
        }

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            let count = max(lhs.components.count, rhs.components.count)
            for index in 0..<count {
                let left = index < lhs.components.count ? lhs.components[index] : 0
                let right = index < rhs.components.count ? rhs.components[index] : 0
                if left != right { return left < right }
            }
            if lhs.channel.stabilityRank != rhs.channel.stabilityRank {
                return lhs.channel.stabilityRank < rhs.channel.stabilityRank
            }
            return lhs.sequence < rhs.sequence
        }
    }

    enum UpdateError: LocalizedError {
        case invalidResponse
        case invalidRelease

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                AppLanguage.localized("app_update.error.response")
            case .invalidRelease:
                AppLanguage.localized("app_update.error.release")
            }
        }
    }
}

private extension AppUpdateChannel {
    var stabilityRank: Int {
        switch self {
        case .alpha: 0
        case .beta: 1
        case .release: 2
        }
    }
}

private extension String {
    var droppingLeadingV: String {
        first == "v" || first == "V" ? String(dropFirst()) : self
    }
}
