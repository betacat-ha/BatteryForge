#if os(macOS)
import Foundation
import Security
import XCTest
@testable import BatteryForgeCore

final class HelperClientIdentityTests: XCTestCase {
    private func app(marker: String, identifier: String = HelperClientIdentity.appIdentifier) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Fixture.app")
        let contents = app.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        let info = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try marker.write(to: contents.appendingPathComponent("Resources/marker"), atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", app.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let detail = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, detail)
        return app
    }

    private func matches(_ app: URL, requirement text: String) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: 1 << 4), requirement) == errSecSuccess
    }

    func testAdHocSignatureAcceptsApprovedAppAndRejectsSameIdentifierWithDifferentCode() throws {
        let approved = try app(marker: "approved")
        let impostor = try app(marker: "different app with the same identifier")
        let requirement = try HelperClientIdentity.requirement(for: approved)
        XCTAssertTrue(HelperClientIdentity.isValidRequirement(requirement))
        XCTAssertTrue(matches(approved, requirement: requirement))
        XCTAssertFalse(matches(impostor, requirement: requirement))
    }

    func testCopyingApprovedAppPreservesIdentityForPrivilegedInstallation() throws {
        let original = try app(marker: "approved")
        let copy = original.deletingLastPathComponent().appendingPathComponent("Copied.app")
        try FileManager.default.copyItem(at: original, to: copy)
        XCTAssertEqual(try HelperClientIdentity.requirement(for: original), try HelperClientIdentity.requirement(for: copy))
    }

    func testTamperedResourcesAndWrongIdentifierAreRejected() throws {
        let tampered = try app(marker: "approved")
        try "tampered".write(to: tampered.appendingPathComponent("Contents/Resources/marker"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try HelperClientIdentity.requirement(for: tampered))
        let wrongIdentifier = try app(marker: "unrelated app", identifier: "com.example.other")
        XCTAssertThrowsError(try HelperClientIdentity.requirement(for: wrongIdentifier))
    }

    func testUserWritableTrustRecordCannotAuthorizeAClient() throws {
        guard geteuid() != 0 else { throw XCTSkip("Requires an unprivileged test user") }
        let app = try app(marker: "approved")
        let record = app.deletingLastPathComponent().appendingPathComponent("client-requirement")
        try HelperClientIdentity.requirement(for: app).write(to: record, atomically: true, encoding: .utf8)
        XCTAssertNil(HelperClientIdentity.trustedRequirement(at: record))
        XCTAssertFalse(HelperClientIdentity.isValidRequirement("not a signing requirement"))
    }
}
#endif
