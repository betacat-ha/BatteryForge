import Foundation

if CommandLine.arguments.dropFirst().first == "--version" {
    FileHandle.standardOutput.write(Data("\(helperVersion)\n".utf8))
    exit(0)
}

guard geteuid() == 0 else {
    FileHandle.standardError.write(Data("BatteryForgeHelper must run as root\n".utf8))
    exit(1)
}

HelperDaemon.shared.run()
