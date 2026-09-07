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

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return percent.map { HelperBatteryState(percent: $0, adapterPresent: false, temperature: nil) }
        }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = unmanaged?.takeRetainedValue() as? [String: Any]
        else {
            return percent.map { HelperBatteryState(percent: $0, adapterPresent: false, temperature: nil) }
        }

        let registryPercent = (values["CurrentCapacity"] as? NSNumber)?.intValue
        let adapterPresent = values["AdapterDetails"] != nil
        let temperature = (values["Temperature"] as? NSNumber).map { $0.doubleValue / 10 - 273.15 }
        guard let finalPercent = percent ?? registryPercent else { return nil }
        return HelperBatteryState(
            percent: finalPercent,
            adapterPresent: adapterPresent,
            temperature: temperature
        )
    }
}
