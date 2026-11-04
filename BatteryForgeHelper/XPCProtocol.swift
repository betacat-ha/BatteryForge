import Foundation

let helperMachServiceName = "com.betacat.batteryforge.helper"
let helperVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
let helperBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

struct HelperMessagePayload: Codable {
    let key: String
    let arguments: [String]

    static func encode(_ key: String, _ arguments: [CustomStringConvertible] = []) -> String {
        let payload = HelperMessagePayload(key: key, arguments: arguments.map(\.description))
        guard let data = try? JSONEncoder().encode(payload) else { return key }
        return String(decoding: data, as: UTF8.self)
    }
}

struct HelperHistoryEntry: Codable {
    let id: UUID
    let timestamp: Date
    let kind: String
    let batteryPercent: Int?
    let lower: Int
    let upper: Int
    let completedCycles: Int
    let highLoad: Bool
    let stressWorkers: Int
    let gpuLoad: Bool
    let message: String
}

@objc(BatteryHelperProtocol)
protocol BatteryHelperProtocol {
    func configure(
        lower: Int,
        upper: Int,
        highLoad: Bool,
        stressWorkers: Int,
        gpuLoad: Bool,
        thermalProtectionEnabled: Bool,
        thermalThreshold: Double,
        reply: @escaping (Bool, String) -> Void
    )
    func stop(reply: @escaping (Bool, String) -> Void)
    func status(reply: @escaping (Bool, String, Int, Bool, String) -> Void)
    func history(reply: @escaping (String) -> Void)
    func clearHistory(reply: @escaping (Bool, String) -> Void)
}
