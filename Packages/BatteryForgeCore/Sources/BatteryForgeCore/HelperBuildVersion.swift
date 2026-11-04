import Foundation

/// Release versions identify shipped helper changes; builds distinguish development iterations.
public struct HelperBuildVersion: Equatable, Sendable {
    public let version: String
    public let build: String?

    public init(version: String, build: String?) {
        self.version = version
        self.build = build
    }

    public func displayValue(includeBuild: Bool = false) -> String {
        guard includeBuild, let build else { return version }
        return "\(version) (Build \(build))"
    }

    public func needsUpdate(to bundled: HelperBuildVersion, compareBuilds: Bool = false) -> Bool {
        guard let installedComponents = Self.components(version),
              let bundledComponents = Self.components(bundled.version)
        else { return true }
        let versionOrder = Self.compare(installedComponents, bundledComponents)
        if versionOrder != 0 { return versionOrder < 0 }

        // Shipped apps update helpers by release version. Only development
        // builds compare build numbers within the same release version.
        guard compareBuilds else { return false }
        guard let build, let bundledBuild = bundled.build,
              let installedBuildComponents = Self.components(build),
              let bundledBuildComponents = Self.components(bundledBuild)
        else { return true }
        return Self.compare(installedBuildComponents, bundledBuildComponents) < 0
    }

    private static func components(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        var result: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(part) else { return nil }
            result.append(number)
        }
        return result.isEmpty ? nil : result
    }

    private static func compare(_ lhs: [Int], _ rhs: [Int]) -> Int {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}
