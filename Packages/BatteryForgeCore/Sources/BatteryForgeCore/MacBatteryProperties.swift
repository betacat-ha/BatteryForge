#if os(macOS)
import Foundation
import IOKit

/// Reads both the legacy battery layout and the layout with per-pack data.
public enum MacBatteryRegistry {
    public struct Reading {
        public let properties: [String: Any]
        public let packProperties: [String: Any]
    }

    public static func read() -> Reading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard var values = properties(of: service) else { return nil }
        mergeBatteryData(into: &values)
        var packProperties: [String: Any] = [:]

        // Newer drivers expose temperature and other gauge readings on a pack
        // child. Only use a single pack as a fallback for whole-battery values.
        var iterator: io_iterator_t = 0
        if IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            var packs: [[String: Any]] = []
            while case let child = IOIteratorNext(iterator), child != 0 {
                defer { IOObjectRelease(child) }
                if IOObjectConformsTo(child, "AppleSmartBatteryPack") != 0,
                   var pack = properties(of: child) {
                    mergeBatteryData(into: &pack)
                    packs.append(pack)
                }
            }
            if let pack = packs.first, packs.count == 1 {
                packProperties = pack
            }
        }
        return Reading(properties: values, packProperties: packProperties)
    }

    private static func properties(of entry: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS
        else { return nil }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    private static func mergeBatteryData(into values: inout [String: Any]) {
        if let data = values["BatteryData"] as? [String: Any] {
            values.merge(data) { existing, _ in existing }
        }
    }
}

public enum MacBatteryProperties {
    public static func chargePercent(in values: [String: Any]) -> Int? {
        let data = values["BatteryData"] as? [String: Any] ?? [:]
        guard let current = (values["CurrentCapacity"] ?? data["CurrentCapacity"]) as? NSNumber,
              let maximum = (values["MaxCapacity"] ?? data["MaxCapacity"]) as? NSNumber,
              maximum.doubleValue > 0, current.doubleValue >= 0,
              current.doubleValue <= maximum.doubleValue
        else { return nil }
        return Int((current.doubleValue / maximum.doubleValue * 100).rounded())
    }

    public static func apply(
        _ values: [String: Any],
        packProperties: [String: Any] = [:],
        to snapshot: inout BatterySnapshot
    ) {
        let data = values["BatteryData"] as? [String: Any] ?? [:]
        func number(_ key: String) -> NSNumber? {
            (values[key] ?? data[key] ?? packProperties[key]) as? NSNumber
        }
        func integer(_ key: String) -> Int? { number(key)?.intValue }

        snapshot.currentCapacity = integer("AppleRawCurrentCapacity")
        snapshot.maximumCapacity = integer("AppleRawMaxCapacity")
            ?? integer("FullChargeCapacity")
        // CurrentCapacity and MaxCapacity may be normalized percentages. They
        // are physical capacities only when MaxCapacity is greater than 100.
        if let maximum = integer("MaxCapacity"), maximum > 100 {
            snapshot.maximumCapacity = snapshot.maximumCapacity ?? maximum
            snapshot.currentCapacity = snapshot.currentCapacity ?? integer("CurrentCapacity")
        }
        snapshot.designCapacity = integer("DesignCapacity")
        snapshot.voltage = integer("Voltage") ?? integer("AppleRawBatteryVoltage")
        snapshot.amperage = integer("Amperage") ?? integer("InstantAmperage")
        snapshot.cycleCount = integer("CycleCount")
        snapshot.isFullyCharged = number("FullyCharged")?.boolValue ?? snapshot.isFullyCharged
        snapshot.isCharging = number("IsCharging")?.boolValue ?? snapshot.isCharging
        snapshot.isConnectedToAC = number("ExternalConnected")?.boolValue ?? snapshot.isConnectedToAC
        let celsius: Double?
        if let raw = (values["Temperature"] ?? data["Temperature"]) as? NSNumber {
            // The legacy AppleSmartBattery property uses Smart Battery 0.1 K.
            celsius = raw.doubleValue / 10 - 273.15
        } else if let raw = packProperties["Temperature"] as? NSNumber {
            // AppleSmartBatteryPack/BatteryData publishes hundredths of °C.
            // Keep its origin separate: both encodings can look plausible.
            celsius = raw.doubleValue / 100
        } else {
            celsius = nil
        }
        if let celsius, (-40...100).contains(celsius) {
            snapshot.temperature = celsius
        }
    }
}
#endif
