#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$project_root/build/iphone-free"
mkdir -p "$output"
cd "$project_root/ios"
xcodebuild -version | tee "$output/environment.txt"
xcodegen generate 2>&1 | tee "$output/xcodegen.log"

common=(-project DropMP4.xcodeproj -scheme DropMP4Free -configuration Debug COMPILER_INDEX_STORE_ENABLE=NO)
xcodebuild "${common[@]}" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$output/Simulator" \
  -resultBundlePath "$output/FreeBuild.xcresult" \
  build-for-testing 2>&1 | tee "$output/simulator-build.log"

# This device build never receives a developer certificate or Apple credentials.
xcodebuild -project DropMP4.xcodeproj -scheme DropMP4Free -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$output/iPhone" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build 2>&1 | tee "$output/iphone-build.log"
python3 "$project_root/scripts/package_iphone.py" \
  "$output/iPhone/Build/Products/Release-iphoneos/DropMP4Free.app" \
  "$output/DropMP4-Free-unsigned.ipa"

xcrun simctl list devices available --json > "$output/simulators.json"
simulator_id="$(python3 "$project_root/scripts/select_simulator.py" "$output/simulators.json")"
trap 'xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true' EXIT
xcrun simctl bootstatus "$simulator_id" -b 2>&1 | tee "$output/simulator-boot.log"
xcodebuild "${common[@]}" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- \
  -destination "platform=iOS Simulator,id=$simulator_id" -destination-timeout 120 \
  -derivedDataPath "$output/Simulator" -resultBundlePath "$output/FreeTests.xcresult" \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 120 \
  test-without-building 2>&1 | tee "$output/simulator-tests.log"
xcrun xcresulttool get test-results summary --path "$output/FreeTests.xcresult" > "$output/test-summary.json"
python3 "$project_root/scripts/verify_ios_results.py" "$output/test-summary.json" --expected 9
