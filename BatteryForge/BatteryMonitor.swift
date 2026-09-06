import Combine
import Foundation
import IOKit
import IOKit.ps

struct BatterySnapshot: Equatable {
    var chargePercent = 0
    var isCharging = false
    var isConnectedToAC = false
    var isFullyCharged = false
    var currentCapacity: Int?
    var maximumCapacity: Int?
    var designCapacity: Int?
    var voltage: Int?
    var amperage: Int?
    var cycleCount: Int?
    var temperature: Double?
    var timeRemaining: Int?
    var healthCondition: String?
    var systemHealthPercent: Int?
    var batteryName: String?
    var lastUpdated = Date()

    var healthPercent: Int? {
        guard let maximumCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return min(Int((Double(maximumCapacity) / Double(designCapacity) * 100).rounded()), 100)
    }

    var power: Double? {
        guard let voltage, let amperage else { return nil }
        return Double(voltage * amperage) / 1_000_000
    }

    var stateDescription: String {
        if isFullyCharged { return String(localized: "battery.state.fully_charged") }
        if isCharging { return String(localized: "battery.state.charging") }
        if isConnectedToAC { return String(localized: "battery.state.ac_connected") }
        return String(localized: "battery.state.on_battery")
    }

    static let preview = BatterySnapshot(
        chargePercent: 76,
        isCharging: false,
        isConnectedToAC: false,
        currentCapacity: 3_842,
        maximumCapacity: 5_012,
        designCapacity: 5_103,
        voltage: 12_143,
        amperage: -1_184,
        cycleCount: 128,
        temperature: 31.4,
        timeRemaining: 214,
        healthCondition: "良好",
        systemHealthPercent: 98,
        batteryName: "内置电池"
    )
}

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot()
    @Published private(set) var hasBattery = true

    private var timer: AnyCancellable?
    private var isReadingSystemHealth = false
    private var lastSystemHealthRead = Date.distantPast

    init(startMonitoring: Bool = true, initialSnapshot: BatterySnapshot? = nil) {
        if let initialSnapshot {
            snapshot = initialSnapshot
        }
        if startMonitoring {
            refresh()
            timer = Timer.publish(every: 5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.refresh() }
        }
    }

    func refresh() {
        var next = BatterySnapshot()
        next.systemHealthPercent = snapshot.systemHealthPercent
        let powerSourceFound = readPowerSource(into: &next)
        let smartBatteryFound = readSmartBattery(into: &next)
        hasBattery = powerSourceFound || smartBatteryFound
        next.lastUpdated = Date()
        snapshot = next
        refreshSystemHealthIfNeeded()
    }

    private func refreshSystemHealthIfNeeded() {
        guard !isReadingSystemHealth,
              Date().timeIntervalSince(lastSystemHealthRead) >= 300
        else { return }

        isReadingSystemHealth = true
        Task { [weak self] in
            let percent = await Task.detached(priority: .utility) {
                SystemBatteryHealthReader.readPercent()
            }.value
            guard let self else { return }
            self.isReadingSystemHealth = false
            self.lastSystemHealthRead = Date()
            guard let percent else { return }
            var updated = self.snapshot
            updated.systemHealthPercent = percent
            self.snapshot = updated
        }
    }

    private func readPowerSource(into snapshot: inout BatterySnapshot) -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  (description[kIOPSTypeKey as String] as? String) == (kIOPSInternalBatteryType as String)
            else { continue }

            let current = intValue(description[kIOPSCurrentCapacityKey as String])
            let maximum = intValue(description[kIOPSMaxCapacityKey as String])
            if let current, let maximum, maximum > 0 {
                snapshot.chargePercent = Int((Double(current) / Double(maximum) * 100).rounded())
            }
            snapshot.isCharging = boolValue(description[kIOPSIsChargingKey as String]) ?? false
            snapshot.isConnectedToAC = (description[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
            snapshot.timeRemaining = positiveInt(description[kIOPSTimeToEmptyKey as String])
                ?? positiveInt(description[kIOPSTimeToFullChargeKey as String])
            if let health = description[kIOPSBatteryHealthKey as String] as? String {
                snapshot.healthCondition = localizedHealth(health)
            } else if let condition = description[kIOPSBatteryHealthConditionKey as String] as? String {
                snapshot.healthCondition = localizedHealth(condition)
            }
            snapshot.batteryName = description[kIOPSNameKey as String] as? String
            return true
        }
        return false
    }

    private func readSmartBattery(into snapshot: inout BatterySnapshot) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanagedProperties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any]
        else { return false }

        snapshot.currentCapacity = intValue(properties["AppleRawCurrentCapacity"])
            ?? intValue(properties["CurrentCapacity"])
        snapshot.maximumCapacity = intValue(properties["AppleRawMaxCapacity"])
            ?? intValue(properties["MaxCapacity"])
        snapshot.designCapacity = intValue(properties["DesignCapacity"])
        snapshot.voltage = intValue(properties["Voltage"])
        snapshot.amperage = intValue(properties["Amperage"])
        snapshot.cycleCount = intValue(properties["CycleCount"])
        snapshot.isFullyCharged = boolValue(properties["FullyCharged"]) ?? false
        snapshot.isCharging = boolValue(properties["IsCharging"]) ?? snapshot.isCharging
        snapshot.isConnectedToAC = boolValue(properties["ExternalConnected"]) ?? snapshot.isConnectedToAC

        if let rawTemperature = doubleValue(properties["Temperature"]) {
            // AppleSmartBattery reports temperature in tenths of a kelvin.
            snapshot.temperature = rawTemperature / 10 - 273.15
        }

        if snapshot.healthCondition != nil {
            // Prefer the public power-source health value when the system supplies it.
        } else if let health = properties["BatteryHealth"] as? String {
            snapshot.healthCondition = localizedHealth(health)
        } else if let condition = properties["BatteryHealthCondition"] as? String {
            snapshot.healthCondition = localizedHealth(condition)
        } else if let healthPercent = snapshot.healthPercent {
            snapshot.healthCondition = healthPercent >= 80
                ? String(localized: "battery.health.good")
                : String(localized: "battery.health.service_recommended")
        }
        return true
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    private func positiveInt(_ value: Any?) -> Int? {
        guard let value = intValue(value), value >= 0 else { return nil }
        return value
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return value as? Double
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        return value as? Bool
    }

    private func localizedHealth(_ value: String) -> String {
        switch value.lowercased() {
        case "good": String(localized: "battery.health.good")
        case "fair": String(localized: "battery.health.normal")
        case "poor", "check battery", "service battery": String(localized: "battery.health.service_recommended")
        default: value
        }
    }
}

private enum SystemBatteryHealthReader {
    nonisolated static func readPercent() -> Int? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        process.standardOutput = output
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let root = try? JSONSerialization.jsonObject(
                with: data
              ) as? [String: Any],
              let entries = root["SPPowerDataType"] as? [[String: Any]]
        else { return nil }

        for entry in entries {
            guard let health = entry["sppower_battery_health_info"] as? [String: Any],
                  let rawValue = health["sppower_battery_health_maximum_capacity"] as? String
            else { continue }
            let digits = rawValue.filter(\.isNumber)
            guard let percent = Int(digits) else { continue }
            return min(max(percent, 0), 100)
        }
        return nil
    }
}
