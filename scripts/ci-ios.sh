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
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  "CODE_SIGN_IDENTITY="
  COMPILER_INDEX_STORE_ENABLE=NO
)

# XCTest is compiled here; no simulator boot or provisioning is required.
xcodebuild "${common[@]}" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$output/DerivedData-simulator" \
  -resultBundlePath "$output/SimulatorBuild.xcresult" \
  build-for-testing 2>&1 | tee "$output/simulator-build.log"

# Catch differences between Simulator and actual iPhone SDK compilation.
# An unsigned iPhone build is NOT an installable IPA.
xcodebuild "${common[@]}" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$output/DerivedData-iphone" \
  -resultBundlePath "$output/iPhoneBuild.xcresult" \
  build 2>&1 | tee "$output/iphone-build.log"
