"""Require all four XCTest cases to actually pass; no empty or skipped green runs."""
import json
import os
from pathlib import Path
import sys

result = json.loads(Path(sys.argv[1]).read_text())
counts = {key: result.get(key) for key in
          ["totalTestCount", "passedTests", "failedTests", "skippedTests"]}
expected = {"totalTestCount": 4, "passedTests": 4, "failedTests": 0, "skippedTests": 0}
if counts != expected:
    raise SystemExit(f"Expected four passed, zero failed/skipped XCTest cases; got {counts}")
message = "iOS XCTest: 4 passed, 0 failed, 0 skipped."
print(message)
if os.getenv("GITHUB_STEP_SUMMARY"):
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
        output.write("\n### iOS Simulator test results\n\n" + message + "\n")
