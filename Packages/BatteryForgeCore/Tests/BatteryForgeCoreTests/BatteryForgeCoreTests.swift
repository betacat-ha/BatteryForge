import XCTest
@testable import BatteryForgeCore

final class BatteryForgeCoreTests: XCTestCase {
    func testUnavailableMeasurementsStayUnknown() {
        let snapshot = BatterySnapshot()
        XCTAssertNil(snapshot.healthPercent)
        XCTAssertNil(snapshot.power)
        XCTAssertNil(snapshot.temperature)
        XCTAssertNil(snapshot.cycleCount)
    }

    func testHealthCalculationAndInvalidDesignCapacity() {
        var snapshot = BatterySnapshot()
        snapshot.maximumCapacity = 4800
        snapshot.designCapacity = 5000
        XCTAssertEqual(snapshot.healthPercent, 96)
        snapshot.maximumCapacity = 5100
        XCTAssertEqual(snapshot.healthPercent, 100)
        snapshot.designCapacity = 0
        XCTAssertNil(snapshot.healthPercent)
    }

    func testDischargePowerKeepsItsSign() {
        var snapshot = BatterySnapshot()
        snapshot.voltage = 12000
        snapshot.amperage = -1500
        XCTAssertEqual(snapshot.power, -18)
    }

}
