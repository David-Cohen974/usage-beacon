#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
cd "$SCRIPT_DIR/.."
ROOT_DIR="$PWD"

REQUESTED_CONFIGURATION="${1:-release}"
case "$REQUESTED_CONFIGURATION" in
  debug|Debug|DEBUG) XCODE_CONFIGURATION="Debug" ;;
  release|Release|RELEASE) XCODE_CONFIGURATION="Release" ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

APP_NAME="UsageBeacon"
WIDGET_NAME="UsageBeaconWidget"
VERSION_CONFIGURATION="$ROOT_DIR/Config/Version.xcconfig"

read_version_setting() {
  local key="$1"
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$VERSION_CONFIGURATION" \
    | tail -1 \
    | xargs
}

MARKETING_VERSION="${MARKETING_VERSION:-$(read_version_setting MARKETING_VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(read_version_setting CURRENT_PROJECT_VERSION)}"
ARCHITECTURES="${ARCHITECTURES:-arm64 x86_64}"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/$APP_NAME.zip"
PROJECT_PATH="$ROOT_DIR/UsageBeacon.xcodeproj"
APP_ENTITLEMENTS="$ROOT_DIR/Resources/UsageBeacon.entitlements"
WIDGET_ENTITLEMENTS="$ROOT_DIR/Resources/UsageBeaconWidget.entitlements"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/usagebeacon-xcode-build.XXXXXX")"
STAGED_ROOT="$BUILD_ROOT/Source"
PRODUCTS_ROOT="$BUILD_ROOT/Build/Products"
INTERMEDIATES_ROOT="$BUILD_ROOT/Build/Intermediates"
ARCHIVE_CHECK_DIR="$BUILD_ROOT/ArchiveCheck"
SOURCE_PACKAGES_DIR_PATH="${SOURCE_PACKAGES_DIR_PATH:-$BUILD_ROOT/SourcePackages}"
export SOURCE_PACKAGES_DIR_PATH

cleanup() {
  find "$BUILD_ROOT" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Missing $PROJECT_PATH. Run Scripts/generate-xcode-project.rb first." >&2
  exit 1
fi

# Documents may be stored in iCloud. Reading one byte asks File Provider to
# materialize any cloud-only source before Xcode coordinates the file.
while IFS= read -r -d '' placeholder; do
  echo "Downloading cloud-only build input: ${placeholder#"$ROOT_DIR/"}"
  head -c 1 "$placeholder" >/dev/null
done < <(find "$ROOT_DIR/Sources" "$ROOT_DIR/Resources" "$ROOT_DIR/Config" "$PROJECT_PATH" -type f -flags +dataless -print0)

remaining_placeholder="$(find "$ROOT_DIR/Sources" "$ROOT_DIR/Resources" "$ROOT_DIR/Config" "$PROJECT_PATH" -type f -flags +dataless -print -quit)"
if [[ -n "$remaining_placeholder" ]]; then
  echo "Unable to download required build input: $remaining_placeholder" >&2
  exit 1
fi

# Build outside the File Provider directory so NSFileCoordinator cannot stall
# Xcode while iCloud is synchronizing the working copy.
mkdir -p "$STAGED_ROOT"
ditto --norsrc "$ROOT_DIR/Sources" "$STAGED_ROOT/Sources"
ditto --norsrc "$ROOT_DIR/Resources" "$STAGED_ROOT/Resources"
ditto --norsrc "$ROOT_DIR/Config" "$STAGED_ROOT/Config"
ditto --norsrc "$PROJECT_PATH" "$STAGED_ROOT/UsageBeacon.xcodeproj"

xcodebuild \
  -project "$STAGED_ROOT/UsageBeacon.xcodeproj" \
  -target "$APP_NAME" \
  -configuration "$XCODE_CONFIGURATION" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  SYMROOT="$PRODUCTS_ROOT" \
  OBJROOT="$INTERMEDIATES_ROOT" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ARCHS="$ARCHITECTURES" \
  ONLY_ACTIVE_ARCH=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build

APP_PATH="$PRODUCTS_ROOT/$XCODE_CONFIGURATION/$APP_NAME.app"
WIDGET_PATH="$APP_PATH/Contents/PlugIns/$WIDGET_NAME.appex"
if [[ ! -d "$WIDGET_PATH" ]]; then
  echo "Xcode did not embed the widget extension at $WIDGET_PATH" >&2
  exit 1
fi

CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
      | head -1
  )"
fi
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

sign_nested_code() {
  local bundle="$1"
  if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    codesign --force \
      --preserve-metadata=identifier,entitlements,requirements,flags \
      --sign - "$bundle"
  else
    codesign --force --options runtime --timestamp \
      --preserve-metadata=identifier,entitlements,requirements \
      --sign "$CODE_SIGN_IDENTITY" "$bundle"
  fi
}

if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
  # Sparkle contains a standalone Autoupdate Mach-O in addition to its nested
  # bundles. Sign every executable before signing the enclosing bundles so the
  # hardened-runtime chain is valid for Apple notarization.
  while IFS= read -r nested_executable; do
    if file "$nested_executable" | grep -q 'Mach-O'; then
      sign_nested_code "$nested_executable"
    fi
  done < <(find "$APP_PATH/Contents/Frameworks" -type f -perm -111 -print)

  while IFS= read -r nested_bundle; do
    sign_nested_code "$nested_bundle"
  done < <(
    find "$APP_PATH/Contents/Frameworks" -type d \
      \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) -print \
      | awk -F/ '{ print NF "\t" $0 }' \
      | sort -rn \
      | cut -f2-
  )
fi

if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
  codesign --force --entitlements "$WIDGET_ENTITLEMENTS" --sign - "$WIDGET_PATH"
  codesign --force --entitlements "$APP_ENTITLEMENTS" --sign - "$APP_PATH"
else
  codesign --force --options runtime --timestamp \
    --entitlements "$WIDGET_ENTITLEMENTS" \
    --sign "$CODE_SIGN_IDENTITY" "$WIDGET_PATH"
  codesign --force --options runtime --timestamp \
    --entitlements "$APP_ENTITLEMENTS" \
    --sign "$CODE_SIGN_IDENTITY" "$APP_PATH"
fi

codesign --verify --strict "$WIDGET_PATH"
codesign --verify --deep --strict "$APP_PATH"
test "$(plutil -extract CFBundleVersion raw "$WIDGET_PATH/Contents/Info.plist")" = "$BUILD_NUMBER"
test "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$WIDGET_PATH/Contents/Info.plist")" = "com.apple.widgetkit-extension"
test "$(plutil -extract SUPublicEDKey raw "$APP_PATH/Contents/Info.plist")" = "TsvqpRp6P1+qRLzm/ei62YSGnZvsp//bdQITGnVdm8Y="
test "$(plutil -extract SUFeedURL raw "$APP_PATH/Contents/Info.plist")" = "https://david-cohen974.github.io/usage-beacon/appcast.xml"
test -d "$APP_PATH/Contents/Frameworks/Sparkle.framework"

mkdir -p "$DIST_DIR"
ditto -c -k --norsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"
mkdir -p "$ARCHIVE_CHECK_DIR"
ditto -x -k "$ARCHIVE_PATH" "$ARCHIVE_CHECK_DIR"
codesign --verify --deep --strict "$ARCHIVE_CHECK_DIR/$APP_NAME.app"

echo "Built $ARCHIVE_PATH"
echo "Version $MARKETING_VERSION ($BUILD_NUMBER); architectures: $(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
