"""Require all four XCTest cases to actually pass; no empty or skipped green runs."""
import json
import os
from pathlib import Path
import sys
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("summary", type=Path)
parser.add_argument("--expected", type=int, default=4)
args = parser.parse_args()
result = json.loads(args.summary.read_text())
counts = {key: result.get(key) for key in
          ["totalTestCount", "passedTests", "failedTests", "skippedTests"]}
expected = {"totalTestCount": args.expected, "passedTests": args.expected, "failedTests": 0, "skippedTests": 0}
if counts != expected:
    raise SystemExit(f"Expected {args.expected} passed, zero failed/skipped XCTest cases; got {counts}")
message = f"iOS XCTest: {args.expected} passed, 0 failed, 0 skipped."
print(message)
if os.getenv("GITHUB_STEP_SUMMARY"):
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
        output.write("\n### iOS Simulator test results\n\n" + message + "\n")
