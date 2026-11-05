#!/usr/bin/env bash
# Build CartCloser AI and install it on a USB-connected (or Wi-Fi paired) iPhone, signed with YOUR Apple team.
# Run on a Mac with Xcode, CocoaPods and Flutter installed:
#   TEAM_ID=ABCDE12345 BUNDLE_ID=com.yourname.cartcloser ./cartcloser-ai/scripts/ios_install_mac.sh
# TEAM_ID: Xcode > Settings > Accounts > your team, or developer.apple.com > Membership.
# The signing change is applied to a temporary copy of the project setting, then restored, so git stays clean.
set -euo pipefail
: "${TEAM_ID:?set TEAM_ID to your 10-character Apple Team ID}"
BUNDLE_ID="${BUNDLE_ID:-com.${USER:-me}.cartcloser}"
APP="$(cd "$(dirname "$0")/../flutter_app" && pwd)"
PBX="$APP/ios/Runner.xcodeproj/project.pbxproj"
command -v xcodebuild >/dev/null || { echo "Xcode is required"; exit 1; }
command -v flutter >/dev/null || { echo "Flutter is required: https://docs.flutter.dev/get-started/install/macos"; exit 1; }
cp "$PBX" "$PBX.bak"; trap 'mv "$PBX.bak" "$PBX"' EXIT
python3 "$(dirname "$0")/ios_signing.py" "$PBX" --automatic --bundle-id "$BUNDLE_ID" --team "$TEAM_ID"
cd "$APP"
flutter pub get
DEVICE="${DEVICE:-$(flutter devices --machine | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin) if x.get("targetPlatform")=="ios" and not x.get("emulator")]; print(d[0]["id"] if d else "")')}"
[ -n "$DEVICE" ] || { echo "No iPhone found. Plug it in, unlock it, tap 'Trust', enable Developer Mode (Settings > Privacy & Security), then retry."; exit 1; }
echo "Installing on $DEVICE as $BUNDLE_ID (team $TEAM_ID)…"
flutter run --release -d "$DEVICE" --no-resident
echo "Done. If iOS says 'Untrusted Developer': Settings > General > VPN & Device Management > trust your developer profile."
