import XCTest
@testable import BatteryForgeCore

final class HelperBuildVersionTests: XCTestCase {
    private let bundled = HelperBuildVersion(version: "0.0.6", build: "2")

    func testReleaseUpdatesByVersionRatherThanBuild() {
        XCTAssertTrue(HelperBuildVersion(version: "0.0.5", build: "999").needsUpdate(to: bundled))
        XCTAssertTrue(HelperBuildVersion(version: "0.0.5", build: nil).needsUpdate(to: bundled))
        XCTAssertFalse(HelperBuildVersion(version: "0.0.6", build: "1").needsUpdate(to: bundled))
        XCTAssertFalse(HelperBuildVersion(version: "0.0.6", build: nil).needsUpdate(to: bundled))
        XCTAssertFalse(bundled.needsUpdate(to: bundled))
        XCTAssertFalse(HelperBuildVersion(version: "0.0.7", build: nil).needsUpdate(to: bundled))
    }

    func testDevelopmentUpdatesWithinSameVersionByBuild() {
        XCTAssertTrue(HelperBuildVersion(version: "0.0.6", build: "1").needsUpdate(to: bundled, compareBuilds: true))
        XCTAssertTrue(HelperBuildVersion(version: "0.0.6", build: nil).needsUpdate(to: bundled, compareBuilds: true))
        XCTAssertFalse(bundled.needsUpdate(to: bundled, compareBuilds: true))
        XCTAssertFalse(HelperBuildVersion(version: "0.0.6", build: "10").needsUpdate(to: bundled, compareBuilds: true))
    }

    func testReleaseVersionTakesPrecedenceDuringDevelopment() {
        XCTAssertTrue(HelperBuildVersion(version: "0.0.5", build: "999").needsUpdate(to: bundled, compareBuilds: true))
        XCTAssertFalse(HelperBuildVersion(version: "0.0.7", build: nil).needsUpdate(to: bundled, compareBuilds: true))
    }

    func testNumericAndDottedBuildComparisonDuringDevelopment() {
        XCTAssertFalse(HelperBuildVersion(version: "0.0.6.0", build: "2.0").needsUpdate(to: bundled, compareBuilds: true))
        XCTAssertTrue(bundled.needsUpdate(to: HelperBuildVersion(version: "0.0.6", build: "10"), compareBuilds: true))
        XCTAssertTrue(HelperBuildVersion(version: "0.0.6", build: "2.9").needsUpdate(
            to: HelperBuildVersion(version: "0.0.6", build: "2.10"), compareBuilds: true
        ))
    }

    func testInvalidBuildMetadataOnlyRequiresDevelopmentUpdate() {
        for build in ["", "-1", "beta", "1..2", "999999999999999999999999999999"] {
            let installed = HelperBuildVersion(version: "0.0.6", build: build)
            XCTAssertTrue(installed.needsUpdate(to: bundled, compareBuilds: true))
            XCTAssertFalse(installed.needsUpdate(to: bundled))
        }
        XCTAssertTrue(HelperBuildVersion(version: "invalid", build: "2").needsUpdate(to: bundled))
    }

    func testDisplayOnlyIncludesBuildWhenRequested() {
        XCTAssertEqual(bundled.displayValue(), "0.0.6")
        XCTAssertEqual(bundled.displayValue(includeBuild: true), "0.0.6 (Build 2)")
        XCTAssertEqual(HelperBuildVersion(version: "0.0.6", build: nil).displayValue(includeBuild: true), "0.0.6")
    }
}
