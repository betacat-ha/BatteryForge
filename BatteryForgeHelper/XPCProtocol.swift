import Foundation

let helperMachServiceName = "com.betacat.batteryforge.helper"

@objc(BatteryHelperProtocol)
protocol BatteryHelperProtocol {
    func configure(
        lower: Int,
        upper: Int,
        highLoad: Bool,
        stressWorkers: Int,
        gpuLoad: Bool,
        reply: @escaping (Bool, String) -> Void
    )
    func stop(reply: @escaping (Bool, String) -> Void)
    func status(reply: @escaping (Bool, String, Int, Bool, String) -> Void)
}
