#if os(macOS)
import XCTest
@testable import BatteryForgeCore

final class MacBatteryPropertiesTests: XCTestCase {
    func testNestedCapacitiesAfterSystemUpdate() {
        let values: [String: Any] = [
            "CurrentCapacity": 100, "MaxCapacity": 100,
            "Voltage": 12908, "Amperage": 0, "CycleCount": 0,
            "BatteryData": [
                "AppleRawCurrentCapacity": 6029, "AppleRawMaxCapacity": 6076,
                "DesignCapacity": 6075, "CurrentCapacity": 100, "MaxCapacity": 100
            ]
        ]
        var snapshot = BatterySnapshot()
        MacBatteryProperties.apply(values, to: &snapshot)
        XCTAssertEqual(snapshot.currentCapacity, 6029)
        XCTAssertEqual(snapshot.maximumCapacity, 6076)
        XCTAssertEqual(snapshot.designCapacity, 6075)
        XCTAssertEqual(snapshot.healthPercent, 100)
        XCTAssertEqual(snapshot.voltage, 12908)
        XCTAssertEqual(snapshot.cycleCount, 0)
        XCTAssertEqual(MacBatteryProperties.chargePercent(in: values), 100)
    }

    func testLegacyPhysicalCapacitiesAndTemperature() throws {
        let values: [String: Any] = [
            "CurrentCapacity": 2400, "MaxCapacity": 4800,
            "DesignCapacity": 5000, "Temperature": 3031,
            "Amperage": NSNumber(value: Int64(-1500)), "ExternalConnected": true
        ]
        var snapshot = BatterySnapshot()
        MacBatteryProperties.apply(values, to: &snapshot)
        XCTAssertEqual(snapshot.currentCapacity, 2400)
        XCTAssertEqual(snapshot.maximumCapacity, 4800)
        XCTAssertEqual(snapshot.healthPercent, 96)
        XCTAssertEqual(try XCTUnwrap(snapshot.temperature), 29.95, accuracy: 0.01)
        XCTAssertEqual(snapshot.amperage, -1500)
        XCTAssertTrue(snapshot.isConnectedToAC)
        XCTAssertEqual(MacBatteryProperties.chargePercent(in: values), 50)
    }

    func testPackTemperatureUsesCentiCelsiusRatherThanLegacyKelvin() throws {
        var snapshot = BatterySnapshot()
        MacBatteryProperties.apply(
            ["CurrentCapacity": 100, "MaxCapacity": 100],
            packProperties: ["Temperature": 3139, "AppleRawMaxCapacity": 6076],
            to: &snapshot
        )
        XCTAssertEqual(try XCTUnwrap(snapshot.temperature), 31.39, accuracy: 0.001)
        XCTAssertEqual(snapshot.maximumCapacity, 6076)
    }

    func testLegacyTemperatureKeepsItsUnitWhenPackAlsoExists() throws {
        var snapshot = BatterySnapshot()
        MacBatteryProperties.apply(
            ["Temperature": 3031], packProperties: ["Temperature": 3139], to: &snapshot
        )
        XCTAssertEqual(try XCTUnwrap(snapshot.temperature), 29.95, accuracy: 0.001)
    }

    func testInvalidPackTemperatureStaysUnknown() {
        var snapshot = BatterySnapshot()
        MacBatteryProperties.apply([:], packProperties: ["Temperature": 65535], to: &snapshot)
        XCTAssertNil(snapshot.temperature)
    }

    func testNormalizedCapacityIsNotMilliamps() {
        var snapshot = BatterySnapshot()
        MacBatteryProperties.apply(["CurrentCapacity": 73, "MaxCapacity": 100], to: &snapshot)
        XCTAssertNil(snapshot.currentCapacity)
        XCTAssertNil(snapshot.maximumCapacity)
        XCTAssertNil(snapshot.healthPercent)
    }

    func testRootValuesTakePrecedenceAndUnknownTemperatureStaysUnknown() {
        var snapshot = BatterySnapshot()
        MacBatteryProperties.apply([
            "AppleRawMaxCapacity": 4800, "Temperature": 0,
            "BatteryData": ["AppleRawMaxCapacity": 4700]
        ], to: &snapshot)
        XCTAssertEqual(snapshot.maximumCapacity, 4800)
        XCTAssertNil(snapshot.temperature)
        XCTAssertNil(MacBatteryProperties.chargePercent(in: ["MaxCapacity": 0]))
    }
}
#endif
