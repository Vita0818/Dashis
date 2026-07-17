#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Dashis"
BUNDLE_ID="com.Vita0818.DashisMac"
CONFIGURATION="${DASHIS_CONFIGURATION:-Debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Dashis.xcodeproj"
TMP_ROOT="${TMPDIR:-/tmp}"
DERIVED_DATA="${DASHIS_DERIVED_DATA:-${TMP_ROOT%/}/dashis-xcode-derived-data}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_NAME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    ENABLE_DEBUG_DYLIB=NO \
    build
}

prepare_app_for_launch() {
  xattr -dr com.apple.provenance "$APP_BUNDLE" >/dev/null 2>&1 || true
  xattr -dr com.apple.quarantine "$APP_BUNDLE" >/dev/null 2>&1 || true
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
  sleep 2
  pgrep -x "$APP_NAME" >/dev/null
}

case "$MODE" in
  run|--run)
    stop_app
    build_app
    prepare_app_for_launch
    open_app
    ;;
  --debug|debug)
    stop_app
    build_app
    prepare_app_for_launch
    lldb -- "$APP_EXECUTABLE"
    ;;
  --logs|logs)
    stop_app
    build_app
    prepare_app_for_launch
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_app
    build_app
    prepare_app_for_launch
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\" OR subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stop_app
    build_app
    prepare_app_for_launch
    open_app
    verify_app
    echo "$APP_NAME is running from $APP_BUNDLE"
    ;;
  *)
    usage
    exit 2
    ;;
esac
