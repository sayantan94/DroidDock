#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if ! command -v pkg-config >/dev/null || ! pkg-config --exists libmtp; then
  echo 'Install build dependencies with: brew install libmtp pkg-config' >&2
  exit 1
fi
swift build -c "$configuration"
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$PWD/dist/DroidDock.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Frameworks"
cp "$bin_dir/MacDroid" "$app_dir/Contents/MacOS/MacDroid"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/dist"
iconutil -c icns "$PWD/dist/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
python3 scripts/bundle-libraries.py "$app_dir"
cp THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/"
for library in "$app_dir"/Contents/Frameworks/*.dylib; do
  codesign --force --sign - "$library"
done
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
echo "Built $app_dir"
