#!/bin/zsh
set -eu
TASK_ROOT=${0:A:h}
cd "$TASK_ROOT/.."
python3 iPad/generate_project.py
if [[ ! -f "$TASK_ROOT/.build/katago-iphonesimulator/libQuietKataGo.a" ]]; then
  "$TASK_ROOT/KataGo/build.sh" iphonesimulator
fi
TASK_DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); pads=[v for devices in d["devices"].values() for v in devices if "iPad" in v["name"]]; print(next((v["udid"] for v in pads if v["state"]=="Booted"),pads[-1]["udid"]))')
TASK_STATE=$(xcrun simctl list devices -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["state"] for ds in d["devices"].values() for v in ds if v["udid"]==sys.argv[1]))' "$TASK_DEVICE")
if [[ "$TASK_STATE" != Booted ]]; then xcrun simctl boot "$TASK_DEVICE"; fi
open -a Simulator --args -CurrentDeviceUDID "$TASK_DEVICE"
xcodebuild -quiet -project iPad/QuietGo-iPad.xcodeproj -scheme QuietGo-iPad \
  -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$TASK_DEVICE" \
  -derivedDataPath iPad/DerivedData CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$TASK_DEVICE" "$TASK_ROOT/DerivedData/Build/Products/Debug-iphonesimulator/QuietGo-iPad.app"
xcrun simctl terminate "$TASK_DEVICE" com.davemarvit.QuietGo.iPad >/dev/null 2>&1 || true
xcrun simctl launch "$TASK_DEVICE" com.davemarvit.QuietGo.iPad
