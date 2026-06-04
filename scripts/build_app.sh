#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="EnglishCoach"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"

ICON_PENDING_NAME="AppIconPending"
ICON_COMPLETED_NAME="AppIconCompleted"
ICON_COMPLETED_GLOW_NAME="AppIconCompletedGlow"

ICON_PENDING_SOURCE="${ICON_PENDING_SOURCE:-$ROOT_DIR/Resources/AppIcon-pending-1024.png}"
ICON_COMPLETED_SOURCE="${ICON_COMPLETED_SOURCE:-$ROOT_DIR/Resources/AppIcon-completed-1024.png}"
ICON_COMPLETED_GLOW_SOURCE="${ICON_COMPLETED_GLOW_SOURCE:-$ROOT_DIR/Resources/AppIcon-completed-glow-1024.png}"
DESKTOP_PET_SOURCE="${DESKTOP_PET_SOURCE:-$ROOT_DIR/Resources/DesktopPetSprite.png}"

SDK_CANDIDATE="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
if [[ -d "$SDK_CANDIDATE" ]]; then
  export SDKROOT="$SDK_CANDIDATE"
fi

export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-/tmp/swift-module-cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-module-cache}"

swift build -c release --disable-sandbox

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

if [[ -f "$DESKTOP_PET_SOURCE" ]]; then
  cp "$DESKTOP_PET_SOURCE" "$APP_DIR/Contents/Resources/DesktopPetSprite.png"
fi

ensure_icon_source() {
  local path="$1"
  local variant="$2"

  if [[ ! -f "$path" ]]; then
    mkdir -p "$(dirname "$path")"
    swift "$ROOT_DIR/scripts/generate_icon.swift" "$path" "$variant"
  fi

  if [[ ! -s "$path" ]]; then
    echo "error: failed to generate icon source ($variant) at $path" >&2
    exit 1
  fi
}

ensure_icon_source "$ICON_PENDING_SOURCE" "pending"
ensure_icon_source "$ICON_COMPLETED_SOURCE" "completed"
ensure_icon_source "$ICON_COMPLETED_GLOW_SOURCE" "completed-glow"

build_icns_from_png() {
  local source_png="$1"
  local icon_name="$2"
  local iconset_dir="$ROOT_DIR/.build/${icon_name}.iconset"
  local icon_file="$APP_DIR/Contents/Resources/${icon_name}.icns"

  rm -rf "$iconset_dir"
  mkdir -p "$iconset_dir"

  make_icon() {
    local size="$1"
    local filename="$2"
    sips -z "$size" "$size" "$source_png" --out "$iconset_dir/$filename" >/dev/null
  }

  make_icon 16 "icon_16x16.png"
  make_icon 32 "icon_16x16@2x.png"
  make_icon 32 "icon_32x32.png"
  make_icon 64 "icon_32x32@2x.png"
  make_icon 128 "icon_128x128.png"
  make_icon 256 "icon_128x128@2x.png"
  make_icon 256 "icon_256x256.png"
  make_icon 512 "icon_256x256@2x.png"
  make_icon 512 "icon_512x512.png"
  make_icon 1024 "icon_512x512@2x.png"

  if command -v iconutil >/dev/null 2>&1; then
    if ! iconutil -c icns "$iconset_dir" -o "$icon_file" >/dev/null 2>&1; then
      swift "$ROOT_DIR/scripts/build_icns.swift" "$iconset_dir" "$icon_file"
    fi
  else
    swift "$ROOT_DIR/scripts/build_icns.swift" "$iconset_dir" "$icon_file"
  fi
}

build_icns_from_png "$ICON_PENDING_SOURCE" "$ICON_PENDING_NAME"
build_icns_from_png "$ICON_COMPLETED_SOURCE" "$ICON_COMPLETED_NAME"
build_icns_from_png "$ICON_COMPLETED_GLOW_SOURCE" "$ICON_COMPLETED_GLOW_NAME"

for icon_name in "$ICON_PENDING_NAME" "$ICON_COMPLETED_NAME" "$ICON_COMPLETED_GLOW_NAME"; do
  icon_path="$APP_DIR/Contents/Resources/${icon_name}.icns"
  if [[ ! -s "$icon_path" ]]; then
    echo "error: missing or empty ${icon_path}" >&2
    exit 1
  fi
done

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIconFile</key>
  <string>${ICON_PENDING_NAME}</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.jiangzhe.englishcoach</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAccessibilityUsageDescription</key>
  <string>EnglishCoach 需要辅助功能权限来读取你在其他 App 中选中的文本，以便连续复制两次（⌘C⌘C）时直接翻译。</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>EnglishCoach 在你执行双复制时读取剪贴板内容以完成翻译。</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key>
        <string>用 EnglishCoach 翻译</string>
      </dict>
      <key>NSMessage</key>
      <string>translateText</string>
      <key>NSPortName</key>
      <string>${APP_NAME}</string>
      <key>NSSendTypes</key>
      <array>
        <string>public.plain-text</string>
        <string>public.utf8-plain-text</string>
        <string>NSStringPboardType</string>
      </array>
      <key>NSRequiredContext</key>
      <dict/>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Re-index the rebuilt bundle with Launch Services so macOS knows the new
# Services entries + AppIntents exist. Without this, a fresh build in a
# non-standard location (like dist/) often won't show up in the Services menu
# or in Shortcuts.app until logout/login.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi
if [[ -x /System/Library/CoreServices/pbs ]]; then
  /System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
fi

# Skip code signing — keeps Accessibility permission stable across rebuilds.
# (Ad-hoc signing generates a new hash every build, forcing re-grant.)

# Auto-install to /Applications so the user always runs the latest build.
INSTALL_DIR="/Applications/${APP_NAME}.app"
if [[ -d "$INSTALL_DIR" ]] || [[ -w /Applications ]]; then
  rm -rf "$INSTALL_DIR"
  cp -R "$APP_DIR" "$INSTALL_DIR"
  echo "Installed to: $INSTALL_DIR"
fi

echo "Built app: $APP_DIR"
echo "Open with: open '$APP_DIR'"
echo "Pending icon source: $ICON_PENDING_SOURCE"
echo "Completed icon source: $ICON_COMPLETED_SOURCE"
echo "Completed glow source: $ICON_COMPLETED_GLOW_SOURCE"
echo "Desktop pet source: $DESKTOP_PET_SOURCE"
