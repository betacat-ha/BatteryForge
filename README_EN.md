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
- Prevents idle sleep throughout the cycle and attempts to remain active when the lid is closed with an external display connected.
- Persists cycle thresholds, workload level, GPU preference, and app language.
- Persists cycle start, phase transition, completion, stop, and failure events.
- Supports Simplified Chinese and English and detects helper updates.
- Checks GitHub Releases automatically at launch, supports stable, beta, and alpha update channels, and offers manual checks and downloads from the About page or app menu.

## Requirements

- macOS 14.0 or later; currently verified only on macOS 26.6.1.
- Apple Silicon or Intel Mac (untested); charge control depends on compatible SMC keys being available on the model.

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

## Versions and builds

Change release versions only when preparing a release. The project-level `BATTERYFORGE_HELPER_VERSION` setting controls the helper release version. The macOS app and helper share `CURRENT_PROJECT_VERSION` as their build number; increment that build for fixes within the same release, such as `0.0.5 (Build 2)` to `0.0.5 (Build 3)`. CI already supplies `CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER"`; local builds can override it in Xcode or on the command line.

The helper's `--version` prints its release version and `--build` prints its build number. Legacy installations without build metadata require a one-time update. Helper communication requires a valid team certificate signature; the unsigned build above supports compilation checks and battery monitoring.

## Safety and privacy

BatteryForge performs its monitoring and control locally. Do not change SMC values unless you understand the associated risks. If temperature becomes excessive, power restoration fails, or the system is unsupported, stop the test and verify the Mac's power state immediately.

## License

This project is available under the [GNU General Public License v3.0](LICENSE). Third-party components remain under their respective licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
