#!/bin/zsh
set -eu
PROJECT_DIR="${0:A:h}"
APP_DIR="${ASTER_APP_DIR:-${PROJECT_DIR:h}/Aster.app}"
CONFIGURATION="${ASTER_CONFIGURATION:-release}"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "${PROJECT_DIR:h:h}/work"
WORK="$(mktemp -d "${PROJECT_DIR:h:h}/work/aster-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# The committed icon is regenerated only when its generator changes.
if [[ ! -f "$PROJECT_DIR/Assets/Aster.icns" || "$PROJECT_DIR/Assets/Icon.swift" -nt "$PROJECT_DIR/Assets/Aster.icns" ]]; then
  xcrun swift "$PROJECT_DIR/Assets/Icon.swift" "$WORK/Aster.iconset"
  /usr/bin/iconutil -c icns "$WORK/Aster.iconset" -o "$PROJECT_DIR/Assets/Aster.icns"
  cp "$WORK/Aster.iconset/icon_512x512@2x.png" "$PROJECT_DIR/Assets/Aster.png"
fi
ARCHITECTURES=(${=ASTER_ARCHS:-arm64})
BINARIES=()
for ARCHITECTURE in "${ARCHITECTURES[@]}"; do
  SWIFTPM=(xcrun swift build --package-path "$PROJECT_DIR" -c "$CONFIGURATION" --triple "$ARCHITECTURE-apple-macosx14.0" --product Aster)
  "${SWIFTPM[@]}"
  BINARY="$WORK/Aster-$ARCHITECTURE"
  cp "$("${SWIFTPM[@]}" --show-bin-path)/Aster" "$BINARY"
  BINARIES+=("$BINARY")
done
xcrun lipo -create "${BINARIES[@]}" -output "$APP_DIR/Contents/MacOS/Aster"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
rm -f "$APP_DIR/Contents/Resources/connection.json"
cp -R "$PROJECT_DIR/Localization" "$APP_DIR/Contents/Resources/"
cp "$PROJECT_DIR/Assets/Aster.icns" "$APP_DIR/Contents/Resources/Aster.icns"
if [[ -n "${ASTER_DEVELOPER_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --entitlements "$PROJECT_DIR/Release.entitlements" --sign "$ASTER_DEVELOPER_ID" "$APP_DIR"
  codesign --verify --strict "$APP_DIR"
else
  /usr/bin/python3 "$PROJECT_DIR/sign-local.py" "$APP_DIR"
fi
echo "Aster.app compilada ($CONFIGURATION) en $APP_DIR"
