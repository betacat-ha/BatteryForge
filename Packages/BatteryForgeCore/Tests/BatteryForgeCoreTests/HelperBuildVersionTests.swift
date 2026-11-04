import XCTest
@testable import BatteryForgeCore

final class HelperBuildVersionTests: XCTestCase {
    private let bundled = HelperBuildVersion(version: "0.0.5", build: "2")

    func testSameReleaseCanUpdateByBuild() {
        XCTAssertTrue(HelperBuildVersion(version: "0.0.5", build: "1").needsUpdate(to: bundled))
        XCTAssertFalse(bundled.needsUpdate(to: bundled))
        XCTAssertFalse(HelperBuildVersion(version: "0.0.5", build: "10").needsUpdate(to: bundled))
    }

    func testReleaseVersionTakesPrecedenceOverBuild() {
        XCTAssertTrue(HelperBuildVersion(version: "0.0.4", build: "999").needsUpdate(to: bundled))
        XCTAssertFalse(HelperBuildVersion(version: "0.0.6", build: "1").needsUpdate(to: bundled))
    }

    func testLegacyHelpersMigrateEvenAfterUnreleasedVersionBumps() {
        for version in ["0.0.5", "0.0.6", "0.0.7"] {
            XCTAssertTrue(HelperBuildVersion(version: version, build: nil).needsUpdate(to: bundled))
        }
    }

    func testNumericAndDottedBuildComparison() {
        XCTAssertFalse(HelperBuildVersion(version: "0.0.5.0", build: "2.0").needsUpdate(to: bundled))
        XCTAssertTrue(bundled.needsUpdate(to: HelperBuildVersion(version: "0.0.5", build: "10")))
        XCTAssertTrue(HelperBuildVersion(version: "0.0.5", build: "2.9").needsUpdate(
            to: HelperBuildVersion(version: "0.0.5", build: "2.10")
        ))
    }

    func testInvalidMetadataRequiresUpdate() {
        for build in ["", "-1", "beta", "1..2", "999999999999999999999999999999"] {
            XCTAssertTrue(HelperBuildVersion(version: "0.0.5", build: build).needsUpdate(to: bundled))
        }
        XCTAssertTrue(HelperBuildVersion(version: "invalid", build: "2").needsUpdate(to: bundled))
    }

    func testDisplayDistinguishesReleaseAndBuild() {
        XCTAssertEqual(bundled.displayValue, "0.0.5 (Build 2)")
        XCTAssertEqual(HelperBuildVersion(version: "0.0.5", build: nil).displayValue, "0.0.5")
    }
}
