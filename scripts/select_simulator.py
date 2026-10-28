"""Select an installed, available iPhone simulator compatible with Xcode 16.4."""
import json
from pathlib import Path
import sys

devices = json.loads(Path(sys.argv[1]).read_text())["devices"]
# Do not accidentally select a newer runtime belonging to a different Xcode.
runtime = "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
available = [d for d in devices.get(runtime, [])
             if d.get("isAvailable") and d.get("name", "").startswith("iPhone")]
if not available:
    raise SystemExit("No available iPhone simulator for iOS 18.5 / Xcode 16.4. Inspect simulators.json.")
available.sort(key=lambda d: (d.get("state") != "Booted", d["name"]))
print(available[0]["udid"])
