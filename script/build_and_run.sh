#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PodTrackio"
PACKAGE_EXECUTABLE_NAME="PodcastTracker"
APP_EXECUTABLE_NAME="PodTrackio"
BUNDLE_ID="com.tangenix.podtrackio"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_DIR="$ROOT_DIR/.swift-build"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE_NAME"
DMG_PATH="$ROOT_DIR/$APP_NAME.dmg"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="$SCRATCH_DIR/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$SCRATCH_DIR/swiftpm-module-cache"

build_app() {
  # The Xcode target is the sandboxed App Store distribution and defines
  # APP_STORE, which intentionally omits external-tool features such as
  # yt-dlp playback/download and playlist import. Local runs must use the
  # full SwiftPM product instead.
  mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$DIST_DIR"
  swift build --disable-sandbox -Xswiftc -disable-sandbox --scratch-path "$SCRATCH_DIR"
  local build_dir
  build_dir="$(swift build --show-bin-path --scratch-path "$SCRATCH_DIR")"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$build_dir/$PACKAGE_EXECUTABLE_NAME" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp "$ROOT_DIR/Info.plist" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_EXECUTABLE_NAME" "$APP_CONTENTS/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$APP_CONTENTS/Info.plist" 2>/dev/null || true
  for resource_bundle in "$build_dir"/*.bundle; do
    [[ -d "$resource_bundle" ]] || continue
    ditto "$resource_bundle" "$APP_RESOURCES/$(basename "$resource_bundle")"
  done
  "$DEVELOPER_DIR/usr/bin/actool" \
    "$ROOT_DIR/AppStore/Assets.xcassets" \
    "$ROOT_DIR/PodTrackio.icon" \
    --compile "$APP_RESOURCES" \
    --output-partial-info-plist "$SCRATCH_DIR/assetcatalog_generated_info.plist" \
    --output-format human-readable-text \
    --notices \
    --warnings \
    --app-icon PodTrackio \
    --enable-on-demand-resources NO \
    --development-region en \
    --target-device mac \
    --minimum-deployment-target 26.0 \
    --platform macosx
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
}

verify_app() {
  plutil -lint "$APP_CONTENTS/Info.plist"
  codesign --verify --deep --strict "$APP_BUNDLE"
  test -x "$APP_BINARY"
  test -d "$APP_RESOURCES/PodcastTracker_PodcastTracker.bundle"
  test -d "$APP_RESOURCES/YouTubeKit_YouTubeKit.bundle"
  test -f "$APP_RESOURCES/Assets.car"
  test -f "$APP_RESOURCES/PodTrackio.icns"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_CONTENTS/Info.plist")" = "PodTrackio"
}

create_dmg() {
  local staging_dir
  staging_dir="$(mktemp -d "$DIST_DIR/.${APP_NAME}-dmg.XXXXXX")"
  trap 'rm -rf "$staging_dir"' RETURN

  ditto "$APP_BUNDLE" "$staging_dir/$APP_NAME.app"
  ln -s /Applications "$staging_dir/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$staging_dir" -format UDZO -ov "$DMG_PATH" >/dev/null
  echo "Created $DMG_PATH"
}

stop_app() {
  pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

build_app

case "$MODE" in
  run)
    stop_app
    open_app
    ;;
  --debug|debug)
    stop_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    stop_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    verify_app
    stop_app
    open_app
    sleep 2
    pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null
    echo "$APP_BUNDLE launched successfully"
    ;;
  --verify-only|verify-only)
    verify_app
    echo "$APP_BUNDLE built and verified without launching"
    ;;
  --dmg|dmg)
    create_dmg
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-only|--dmg]" >&2
    exit 2
    ;;
esac
