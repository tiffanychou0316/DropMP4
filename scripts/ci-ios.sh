#!/usr/bin/env bash
# Called explicitly with bash; no executable bit needed after Windows uploads.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$project_root/build/ios-ci"
mkdir -p "$output"

if [[ "$(uname -s)" != Darwin ]]; then
  echo "This build requires a macOS runner with Xcode." >&2
  exit 2
fi

{
  sw_vers
  xcodebuild -version
  xcodegen --version
  xcodebuild -showsdks
} 2>&1 | tee "$output/environment.txt"

cd "$project_root/ios"
xcodegen generate 2>&1 | tee "$output/xcodegen.log"
xcodebuild -list -project DropMP4.xcodeproj 2>&1 | tee "$output/targets.txt"

common=(
  -project DropMP4.xcodeproj
  -scheme DropMP4
  -configuration Debug
  COMPILER_INDEX_STORE_ENABLE=NO
)

# Simulator signing is local ad-hoc signing; no Apple account or certificate.
simulator_signing=(CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO "CODE_SIGN_IDENTITY=-")
unsigned=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "CODE_SIGN_IDENTITY=")

xcodebuild "${common[@]}" \
  "${simulator_signing[@]}" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$output/DerivedData-simulator" \
  -resultBundlePath "$output/SimulatorBuild.xcresult" \
  build-for-testing 2>&1 | tee "$output/simulator-build.log"

xcodebuild "${common[@]}" \
  "${unsigned[@]}" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$output/DerivedData-iphone" \
  -resultBundlePath "$output/iPhoneBuild.xcresult" \
  build 2>&1 | tee "$output/iphone-build.log"

xcrun simctl list devices available --json > "$output/simulators.json"
simulator_id="$(python3 "$project_root/scripts/select_simulator.py" "$output/simulators.json")"
echo "Selected iPhone Simulator: $simulator_id" | tee "$output/selected-simulator.txt"
trap 'xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true' EXIT
xcrun simctl bootstatus "$simulator_id" -b 2>&1 | tee "$output/simulator-boot.log"

# Execute the already-built tests exactly once, on one destination.
xcodebuild "${common[@]}" \
  "${simulator_signing[@]}" \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -destination-timeout 120 \
  -derivedDataPath "$output/DerivedData-simulator" \
  -resultBundlePath "$output/SimulatorTests.xcresult" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  test-without-building 2>&1 | tee "$output/simulator-tests.log"

xcrun xcresulttool get test-results summary \
  --path "$output/SimulatorTests.xcresult" > "$output/test-summary.json"
python3 "$project_root/scripts/verify_ios_results.py" "$output/test-summary.json"
