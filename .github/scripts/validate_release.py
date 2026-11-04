#!/usr/bin/env python3
"""Validate the exact signed app before GitHub Actions publishes its DMG."""

import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(args):
    app = args.app
    helper = app / "Contents/Resources/BatteryForgeHelper"
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    require(info.get("CFBundleIdentifier") == "com.betacat.batteryforge", "Unexpected app identifier")
    require(info.get("CFBundleShortVersionString") == args.version, "App release version mismatch")
    require(info.get("CFBundleVersion") == args.build, "App build number mismatch")
    require(info.get("BatteryForgeHelperVersion") == args.helper_version, "Bundled helper version mismatch")
    require(output(str(helper), "--version") == args.helper_version, "Helper release version mismatch")
    require(output(str(helper), "--build") == args.build, "Helper build number mismatch")
    channel = (app / "Contents/Resources/ReleaseChannel.txt").read_text().strip()
    require(channel == args.channel, "Release channel mismatch")
    require((app / "Contents/Resources/AppIcon.icns").is_file(), "Missing app icon")
    require(
        (app / "Contents/Library/LaunchDaemons/com.betacat.batteryforge.helper.plist").is_file(),
        "Missing helper launch daemon plist",
    )
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    for executable, identifier in [
        (app / "Contents/MacOS/BatteryForge", "com.betacat.batteryforge"),
        (helper, "com.betacat.batteryforge.helper"),
    ]:
        archs = set(output("lipo", "-archs", str(executable)).split())
        require({"arm64", "x86_64"} <= archs, f"Missing universal architecture: {executable.name}")
        signing = subprocess.run(
            ["codesign", "-dv", str(executable)], capture_output=True, text=True, check=True
        ).stderr.splitlines()
        require(f"Identifier={identifier}" in signing, f"Signing identifier mismatch: {executable.name}")
        require("Signature=adhoc" in signing, f"Expected certificate-free ad-hoc signature: {executable.name}")
    requirement = output(str(helper), "--client-requirement", str(app))
    for architecture in ["arm64", "x86_64"]:
        signing = subprocess.run(
            ["codesign", "-dv", "--verbose=4", "--architecture", architecture, str(app)],
            capture_output=True, text=True, check=True,
        ).stderr
        match = re.search(r"^CDHash=([0-9a-f]{40})$", signing, re.MULTILINE)
        require(match is not None and f'cdhash H"{match.group(1)}"' in requirement,
                f"Missing authorized code hash for {architecture}")
    print(f"Verified app {args.version} (Build {args.build}), helper {args.helper_version}, {args.channel}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--helper-version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--channel", required=True, choices=["release", "beta", "alpha"])
    args = parser.parse_args()
    try:
        validate(args)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Release validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
