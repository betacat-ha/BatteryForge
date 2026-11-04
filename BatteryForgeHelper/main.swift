import BatteryForgeCore
import Foundation

guard !helperVersion.isEmpty, !helperBuild.isEmpty else {
    FileHandle.standardError.write(Data("BatteryForgeHelper build metadata is missing\n".utf8))
    exit(1)
}

if CommandLine.arguments.dropFirst().first == "--build" {
    FileHandle.standardOutput.write(Data("\(helperBuild)\n".utf8))
    exit(0)
}

if CommandLine.arguments.dropFirst().first == "--version" {
    FileHandle.standardOutput.write(Data("\(helperVersion)\n".utf8))
    exit(0)
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--client-requirement" {
    do {
        let requirement = try HelperClientIdentity.requirement(for: URL(fileURLWithPath: CommandLine.arguments[2]))
        FileHandle.standardOutput.write(Data("\(requirement)\n".utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Cannot verify client application signature\n".utf8))
        exit(1)
    }
}

guard geteuid() == 0 else {
    FileHandle.standardError.write(Data("BatteryForgeHelper must run as root\n".utf8))
    exit(1)
}

HelperDaemon.shared.run()
