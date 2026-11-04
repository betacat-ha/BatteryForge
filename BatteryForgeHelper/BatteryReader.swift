import BatteryForgeCore
import Foundation
import IOKit
import IOKit.ps

struct HelperBatteryState {
    let percent: Int
    let adapterPresent: Bool
    let temperature: Double?
}

enum HelperBatteryReader {
    static func current() -> HelperBatteryState? {
        var percent: Int?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      (values[kIOPSTypeKey as String] as? String) == (kIOPSInternalBatteryType as String)
                else { continue }
                let current = (values[kIOPSCurrentCapacityKey as String] as? NSNumber)?.intValue
                let max = (values[kIOPSMaxCapacityKey as String] as? NSNumber)?.intValue
                if let current, let max, max > 0 {
                    percent = Int((Double(current) / Double(max) * 100).rounded())
                }
                break
            }
        }

        guard let reading = MacBatteryRegistry.read() else {
            return percent.map { HelperBatteryState(percent: $0, adapterPresent: false, temperature: nil) }
        }
        let values = reading.properties
        var snapshot = BatterySnapshot()
        MacBatteryProperties.apply(values, packProperties: reading.packProperties, to: &snapshot)
        guard let finalPercent = percent ?? MacBatteryProperties.chargePercent(in: values) else { return nil }
        return HelperBatteryState(
            percent: finalPercent,
            adapterPresent: values["AdapterDetails"] != nil,
            temperature: snapshot.temperature
        )
    }
}
