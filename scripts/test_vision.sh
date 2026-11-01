#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
build_dir="$(mktemp -d /tmp/OpenIntake-vision.XXXXXX)"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -target arm64-apple-macos26.0 -parse-as-library \
  -module-cache-path "$build_dir/cache" Sources/IntakeCore/*.swift \
  App/DocumentOCR.swift scripts/vision_smoke.swift -o "$build_dir/vision-smoke"
"$build_dir/vision-smoke"
