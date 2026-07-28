#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$SCRIPT_DIR/Jingyin.xcodeproj"
SCHEME="Jingyin"
BUNDLE_ID="com.reaidea.jingyin"
DEVICE_NAME="${IOS_SIMULATOR:-iPhone 17 Pro}"
DERIVED_DATA="$SCRIPT_DIR/.derived-data"

DEVICE_ID="$(xcrun simctl list devices available | awk -v name="$DEVICE_NAME" '
  index($0, name " (") {
    match($0, /[0-9A-F]{8}-[0-9A-F-]{27,}/)
    if (RSTART) { print substr($0, RSTART, RLENGTH); exit }
  }
')"

if [[ -z "$DEVICE_ID" ]]; then
  echo "未找到可用模拟器：$DEVICE_NAME" >&2
  echo "可通过 IOS_SIMULATOR='iPhone 17 Pro' ./run-ios.sh 指定设备。" >&2
  exit 1
fi

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator
for _ in {1..60}; do
  if xcrun simctl list devices | grep -F "$DEVICE_ID" | grep -q "(Booted)"; then
    break
  fi
  sleep 1
done
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Jingyin.app"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
