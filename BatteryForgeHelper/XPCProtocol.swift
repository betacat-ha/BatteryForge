import Foundation

let helperMachServiceName = "com.betacat.batteryforge.helper"
let helperVersion = "0.0.2"

struct HelperMessagePayload: Codable {
    let key: String
    let arguments: [String]

    static func encode(_ key: String, _ arguments: [CustomStringConvertible] = []) -> String {
        let payload = HelperMessagePayload(key: key, arguments: arguments.map(\.description))
        guard let data = try? JSONEncoder().encode(payload) else { return key }
        return String(decoding: data, as: UTF8.self)
    }
}

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
