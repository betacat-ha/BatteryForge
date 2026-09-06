# BatteryForge

[中文](README.md)

BatteryForge is a macOS battery cycling and stress-testing utility built with SwiftUI. It reads battery data, automatically switches between charging and discharging at configured thresholds, and can run CPU and GPU workloads during discharge.

> [!WARNING]
> This project uses a privileged helper to control supported charging-related SMC keys and can sustain a heavy system load. Doing so may increase battery cycle count, temperature, and hardware wear. Use it only if you understand the risks, keep the Mac adequately cooled, and expect hardware and macOS compatibility to vary.

## Features

- Reads charge level, voltage, current, power, temperature, cycle count, and remaining time.
- Shows design capacity, maximum capacity, calculated battery health, and the system-reported battery health value.
- Resumes charging below the lower threshold and stops charging above the upper threshold while switching to battery power.
- Runs multithreaded CPU and Metal GPU workloads concurrently during discharge.
- Keeps the cycle running in a privileged helper after the main window is closed or the app exits.
- Prevents idle sleep during discharge and attempts to remain active when the lid is closed with an external display connected.
- Persists cycle thresholds, workload level, GPU preference, and app language.
- Supports Simplified Chinese and English and detects helper updates.

## Requirements

- macOS 26.5 or later, matching the current project deployment target.
- Apple Silicon or Intel Mac; charge control depends on compatible SMC keys being available on the model.
- An Xcode version compatible with the current project settings.
- Administrator authorization when installing or updating the helper.

## Building

1. Open `BatteryForge.xcodeproj` in Xcode.
2. Select your Development Team in Signing & Capabilities. Change the app and helper bundle identifiers if necessary.
3. Select the `BatteryForge` scheme and the `My Mac` destination.
4. Build and run.

For an unsigned command-line build:

```sh
xcodebuild \
  -project BatteryForge.xcodeproj \
  -scheme BatteryForge \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

An unsigned build is useful for compilation checks. Installing the privileged helper for normal use still requires appropriate signing and administrator authorization.

## Usage

1. Install or update the Helper Service under Settings.
2. Configure the lower threshold for starting charge and the upper threshold for stopping charge.
3. Enable the CPU/GPU workload and select an intensity if desired.
4. Return to Overview and select Start Cycle.
5. Select Stop Cycle to stop the workload and attempt to restore normal AC power and sleep behavior.

Cycle and workload settings are locked while a cycle is active. Stop the current cycle before changing them.

## Project layout

- `BatteryForge/`: SwiftUI app, battery monitoring, settings, and helper management.
- `BatteryForgeHelper/`: root LaunchDaemon, SMC control, CPU/GPU workload, and sleep management.
- `BatteryForge.xcodeproj/`: Xcode project and shared schemes.
- `THIRD_PARTY_NOTICES.md`: third-party attribution and license notices.

## Safety and privacy

BatteryForge performs its monitoring and control locally. Do not change SMC values unless you understand the associated risks. If temperature becomes excessive, power restoration fails, or the system is unsupported, stop the test and verify the Mac's power state immediately.

## License

This project is available under the [GNU General Public License v3.0](LICENSE). Third-party components remain under their respective licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
