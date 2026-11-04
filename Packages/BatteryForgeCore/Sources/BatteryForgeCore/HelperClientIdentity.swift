#if os(macOS)
import Foundation
import Security

/// Pins the exact app approved by the administrator, including each CPU slice.
public enum HelperClientIdentity {
    public static let requirementPath = "/Library/Application Support/BatteryForge/client-requirement"
    public static let appIdentifier = "com.betacat.batteryforge"

    public static func requirement(for appURL: URL) throws -> String {
        var defaultCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &defaultCode) == errSecSuccess,
              let defaultCode,
              SecStaticCodeCheckValidity(defaultCode, SecCSFlags(rawValue: (1 << 0) | (1 << 4)), nil) == errSecSuccess
        else { throw IdentityError.invalidSignature }

        func hash(of code: SecStaticCode) throws -> String {
            var rawInformation: CFDictionary?
            guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: 1 << 1), &rawInformation) == errSecSuccess,
                  let information = rawInformation as? [String: Any],
                  information[kSecCodeInfoIdentifier as String] as? String == appIdentifier,
                  let hash = information[kSecCodeInfoUnique as String] as? Data, hash.count == 20
            else { throw IdentityError.invalidSignature }
            return hash.map { String(format: "%02x", $0) }.joined()
        }
        // Include the native subtype as well as both distributed app slices.
        var hashes: Set<String> = [try hash(of: defaultCode)]
        for architecture in ["arm64", "x86_64"] {
            var code: SecStaticCode?
            let attributes = [kSecCodeAttributeArchitecture as String: architecture] as CFDictionary
            guard SecStaticCodeCreateWithPathAndAttributes(appURL as CFURL, [], attributes, &code) == errSecSuccess,
                  let code else { continue }
            hashes.insert(try hash(of: code))
        }
        guard !hashes.isEmpty else { throw IdentityError.invalidSignature }
        let alternatives = hashes.sorted().map { "cdhash H\"\($0)\"" }.joined(separator: " or ")
        return "identifier \"\(appIdentifier)\" and (\(alternatives))"
    }

    public static func trustedRequirement(at url: URL = URL(fileURLWithPath: requirementPath)) -> String? {
        // Neither the trust record nor its directory may be writable by a
        // non-root user. Only the privileged installation writes this record.
        for path in [url.path, url.deletingLastPathComponent().path] {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
                  let mode = attributes[.posixPermissions] as? NSNumber,
                  mode.intValue & 0o022 == 0,
                  attributes[.type] as? FileAttributeType != .typeSymbolicLink
            else { return nil }
        }
        guard let data = try? Data(contentsOf: url), data.count <= 4096,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              isValidRequirement(text) else { return nil }
        return text
    }

    public static func isValidRequirement(_ text: String) -> Bool {
        var requirement: SecRequirement?
        return SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess && requirement != nil
    }

    public enum IdentityError: Error {
        case invalidSignature
    }
}
#endif
