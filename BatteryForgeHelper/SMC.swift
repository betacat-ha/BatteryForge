import Foundation
import IOKit

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

enum PowerAction { case normal, discharge }

enum PowerControlError: LocalizedError {
    case unsupported
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: "此 Mac 没有可用的充电控制键"
        case .failed(let detail): "SMC 控制失败：\(detail)"
        }
    }
}

private extension FourCharCode {
    init(smcKey string: String) {
        precondition(string.utf8.count == 4)
        self = string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

private struct SMCParamStruct {
    struct Version {
        var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0
        var reserved: UInt8 = 0; var release: UInt16 = 0
    }
    struct PLimitData {
        var version: UInt16 = 0; var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0
    }
    struct KeyInfo {
        var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

private enum SMCClient {
    private static var connection: io_connect_t = 0

    static func open() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw PowerControlError.unsupported }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw PowerControlError.failed("无法连接 AppleSMC（\(result)）") }
    }

    static func close() {
        if connection != 0 { IOServiceClose(connection) }
        connection = 0
    }

    static func keyExists(_ name: String) -> Bool {
        var input = SMCParamStruct()
        input.key = FourCharCode(smcKey: name)
        input.data8 = 9
        return (try? call(&input)) != nil
    }

    static func write(_ name: String, bytes: [UInt8]) throws {
        var input = SMCParamStruct()
        input.key = FourCharCode(smcKey: name)
        input.keyInfo.dataSize = UInt32(bytes.count)
        input.data8 = 6
        withUnsafeMutableBytes(of: &input.bytes) { $0.copyBytes(from: bytes) }
        _ = try call(&input)
    }

    private static func call(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        guard MemoryLayout<SMCParamStruct>.stride == 80 else { throw PowerControlError.failed("数据结构不兼容") }
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize
        )
        guard result == kIOReturnSuccess, output.result == 0 else {
            if output.result == 132 { throw PowerControlError.unsupported }
            throw PowerControlError.failed("返回码 \(result)/\(output.result)")
        }
        return output
    }
}

enum DirectPowerControl {
    static func apply(_ action: PowerAction) throws {
        try SMCClient.open()
        defer { SMCClient.close() }
        let tahoe = SMCClient.keyExists("CHTE")
        let legacy = SMCClient.keyExists("CH0B") || SMCClient.keyExists("CH0C")
        guard tahoe || legacy else { throw PowerControlError.unsupported }

        if action == .normal {
            try writeIfPresent("CHIE", [0])
            try writeIfPresent("CH0J", [0])
            try writeIfPresent("CH0I", [0])
            if tahoe { try SMCClient.write("CHTE", bytes: [0, 0, 0, 0]) }
            if legacy {
                try writeIfPresent("CH0B", [0]); try writeIfPresent("CH0C", [0])
            }
            return
        }

        if tahoe { try SMCClient.write("CHTE", bytes: [1, 0, 0, 0]) }
        else { try writeIfPresent("CH0B", [2]); try writeIfPresent("CH0C", [2]) }

        if SMCClient.keyExists("CHIE") { try SMCClient.write("CHIE", bytes: [8]) }
        else if SMCClient.keyExists("CH0J") { try SMCClient.write("CH0J", bytes: [1]) }
        else if SMCClient.keyExists("CH0I") { try SMCClient.write("CH0I", bytes: [1]) }
        else {
            try? restoreChargeGate(tahoe: tahoe, legacy: legacy)
            throw PowerControlError.unsupported
        }
    }

    private static func restoreChargeGate(tahoe: Bool, legacy: Bool) throws {
        if tahoe { try SMCClient.write("CHTE", bytes: [0, 0, 0, 0]) }
        if legacy { try writeIfPresent("CH0B", [0]); try writeIfPresent("CH0C", [0]) }
    }

    private static func writeIfPresent(_ key: String, _ bytes: [UInt8]) throws {
        if SMCClient.keyExists(key) { try SMCClient.write(key, bytes: bytes) }
    }
}
