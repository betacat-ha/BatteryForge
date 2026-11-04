import Foundation

public struct BatterySnapshot: Equatable, Sendable {
    public var chargePercent = 0
    public var isCharging = false
    public var isConnectedToAC = false
    public var isFullyCharged = false
    public var currentCapacity: Int?
    public var maximumCapacity: Int?
    public var designCapacity: Int?
    public var voltage: Int?
    public var amperage: Int?
    public var cycleCount: Int?
    public var temperature: Double?
    public var timeRemaining: Int?
    public var healthCondition: String?
    public var systemHealthPercent: Int?
    public var batteryName: String?
    public var lastUpdated = Date()

    public var healthPercent: Int? {
        guard let maximumCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return min(Int((Double(maximumCapacity) / Double(designCapacity) * 100).rounded()), 100)
    }

    public var power: Double? {
        guard let voltage, let amperage else { return nil }
        return Double(voltage * amperage) / 1_000_000
    }

    public init() {}
}
