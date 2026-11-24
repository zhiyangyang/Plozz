#!/usr/bin/env python3
"""Select an available iOS simulator matching the CI build SDK."""

import argparse
import json
import subprocess
import sys


def runtime_version(runtime: str) -> tuple[int, ...]:
    suffix = runtime.rsplit("iOS-", 1)[-1]
    return tuple(int(part) for part in suffix.split("-") if part.isdigit())


def select_device(devices: dict, sdk_version: str) -> tuple[str, str]:
    """Pick the newest available iOS runtime with an iPad device.

    The runner can expose an older runtime whose simulators cannot boot
    (`SimDevice native architecture is nil`) while a newer runtime on the same
    image is healthy. Preferring the newest runtime keeps the hosted suite
    resilient to that provisioning state; the app's deployment target is lower
    than either runtime.
    """
    runtimes = [
        runtime for runtime, items in devices.get("devices", {}).items()
        if runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
        and any(device.get("isAvailable") and "iPad" in device.get("name", "")
                for device in items)
    ]
    if not runtimes:
        raise ValueError(f"No available iPad simulator for iOS {sdk_version}")
    runtimes.sort(key=runtime_version, reverse=True)
    for runtime in runtimes:
        candidates = [
            device for device in devices["devices"][runtime]
            if device.get("isAvailable") and "iPad" in device.get("name", "")
        ]
        candidates.sort(key=lambda device: (
            "iPad Pro" not in device["name"],
            device["name"],
            device["udid"],
        ))
        if candidates:
            return candidates[0]["udid"], candidates[0]["name"]
    raise ValueError(f"No available iPad simulator for iOS {sdk_version}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-version", required=True)
    args = parser.parse_args()
    try:
        result = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "--json"],
            capture_output=True, text=True, check=True, timeout=300,
        )
        identifier, name = select_device(json.loads(result.stdout), args.sdk_version)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"CI simulator selection failed: {error}", file=sys.stderr)
        return 1
    print(f"Selected iOS {args.sdk_version}: {name} ({identifier})", file=sys.stderr)
    print(identifier)
    return 0


if __name__ == "__main__":
    sys.exit(main())
