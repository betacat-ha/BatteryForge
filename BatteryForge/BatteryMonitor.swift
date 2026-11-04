import BatteryForgeCore
import Combine
import Foundation
import IOKit
import IOKit.ps

extension BatterySnapshot {
    var stateDescription: String {
        if isFullyCharged { return AppLanguage.localized("battery.state.fully_charged") }
        if isCharging { return AppLanguage.localized("battery.state.charging") }
        if isConnectedToAC { return AppLanguage.localized("battery.state.ac_connected") }
        return AppLanguage.localized("battery.state.on_battery")
    }

    static var preview: BatterySnapshot {
        var snapshot = BatterySnapshot()
        snapshot.chargePercent = 76
        snapshot.currentCapacity = 3_842
        snapshot.maximumCapacity = 5_012
        snapshot.designCapacity = 5_103
        snapshot.voltage = 12_143
        snapshot.amperage = -1_184
        snapshot.cycleCount = 128
        snapshot.temperature = 31.4
        snapshot.timeRemaining = 214
        snapshot.healthCondition = "良好"
        snapshot.systemHealthPercent = 98
        snapshot.batteryName = "内置电池"
        return snapshot
    }
}

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot()
    @Published private(set) var hasBattery = true

    private var timer: AnyCancellable?
    private var isReadingSystemHealth = false
    private var lastSystemHealthRead = Date.distantPast
    private var rawSystemHealthCondition: String?

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
        let smartBatteryFound = readSmartBattery(into: &next, needsChargePercent: !powerSourceFound)
        if let rawSystemHealthCondition {
            next.healthCondition = localizedHealth(rawSystemHealthCondition)
        }
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
            let reading = await Task.detached(priority: .utility) {
                SystemBatteryHealthReader.read()
            }.value
            guard let self else { return }
            self.isReadingSystemHealth = false
            self.lastSystemHealthRead = Date()
            guard let reading else { return }
            var updated = self.snapshot
            if let percent = reading.percent {
                updated.systemHealthPercent = percent
            }
            if let condition = reading.condition {
                let localizedCondition = self.localizedHealth(condition)
                self.rawSystemHealthCondition = condition
                updated.healthCondition = localizedCondition
            }
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

    private func readSmartBattery(into snapshot: inout BatterySnapshot, needsChargePercent: Bool) -> Bool {
        guard let reading = MacBatteryRegistry.read() else { return false }
        let properties = reading.properties
        MacBatteryProperties.apply(properties, packProperties: reading.packProperties, to: &snapshot)
        if needsChargePercent, let percent = MacBatteryProperties.chargePercent(in: properties) {
            snapshot.chargePercent = percent
        }

        if snapshot.healthCondition != nil {
            // Prefer the public power-source health value when the system supplies it.
        } else if let health = properties["BatteryHealth"] as? String {
            snapshot.healthCondition = localizedHealth(health)
        } else if let condition = properties["BatteryHealthCondition"] as? String {
            snapshot.healthCondition = localizedHealth(condition)
        } else if let healthPercent = snapshot.healthPercent {
            snapshot.healthCondition = healthPercent >= 80
                ? AppLanguage.localized("battery.health.good")
                : AppLanguage.localized("battery.health.service_recommended")
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

    private func boolValue(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        return value as? Bool
    }

    private func localizedHealth(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "good": AppLanguage.localized("battery.health.good")
        case "normal", "fair": AppLanguage.localized("battery.health.normal")
        case "replace soon":
            AppLanguage.localized("battery.health.replace_soon")
        case "replace now":
            AppLanguage.localized("battery.health.replace_now")
        case "service battery":
            AppLanguage.localized("battery.health.service_battery")
        case "poor", "check battery", "service recommended":
            AppLanguage.localized("battery.health.service_recommended")
        default: value
        }
    }
}

private enum SystemBatteryHealthReader {
    struct Reading: Sendable {
        let percent: Int?
        let condition: String?
    }

    nonisolated static func read() -> Reading? {
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
            guard let health = entry["sppower_battery_health_info"] as? [String: Any] else { continue }
            let condition = health["sppower_battery_health"] as? String
            let percent = (health["sppower_battery_health_maximum_capacity"] as? String)
                .flatMap { Int($0.filter(\.isNumber)) }
                .map { min(max($0, 0), 100) }
            if percent != nil || condition != nil {
                return Reading(percent: percent, condition: condition)
            }
        }
        return nil
    }
}
