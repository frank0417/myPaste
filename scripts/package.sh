#!/usr/bin/env bash
# Build Paste.app and package into a distributable .dmg (and optional .pkg).
# Must run on macOS with Xcode Command Line Tools installed.
#
# Usage:
#   ./scripts/package.sh                  # unsigned/ad-hoc Release .app + .dmg
#   ./scripts/package.sh --sign           # Developer ID Application signing
#   ./scripts/package.sh --sign --pkg     # also create .pkg installer
#   ./scripts/package.sh --sign --notarize
#   ./scripts/package.sh --app-store      # archive + export for App Store Connect
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Paste/Paste.xcodeproj"
SCHEME="Paste"
CONFIG="Release"
VERSION="${MARKETING_VERSION:-1.0.0}"
BUILD_NUMBER="${CURRENT_PROJECT_VERSION:-1}"
BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.mypaste.Paste}"
APP_NAME="Paste"
DIST="$ROOT/dist"
DERIVED="$ROOT/build/DerivedData"
ARCHIVE_PATH="$ROOT/build/Paste.xcarchive"

SIGN=0
MAKE_PKG=0
NOTARIZE=0
APP_STORE=0
IDENTITY="${CODE_SIGN_IDENTITY:-}"
TEAM_ID="${DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-PasteNotary}"

usage() {
  cat <<'EOF'
Build Paste.app and package into .dmg / optional .pkg (macOS + Xcode required).

Usage:
  ./scripts/package.sh                  # ad-hoc Release .app + .dmg
  ./scripts/package.sh --sign           # Developer ID signing
  ./scripts/package.sh --sign --pkg     # also create .pkg
  ./scripts/package.sh --sign --notarize
  ./scripts/package.sh --app-store
  ./scripts/package.sh --version 1.0.1
  ./scripts/package.sh --identity "Developer ID Application: Name (TEAMID)"
  ./scripts/package.sh --team TEAMID
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign) SIGN=1; shift ;;
    --pkg) MAKE_PKG=1; shift ;;
    --notarize) NOTARIZE=1; SIGN=1; shift ;;
    --app-store) APP_STORE=1; SIGN=1; shift ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --team) TEAM_ID="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --help|-h) usage 0 ;;
    *) echo "Unknown option: $1"; usage 1 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  cat <<EOF
❌ 当前环境是 $(uname -s)，无法在此编译 macOS 应用。

请在 Mac 上执行：
  ./scripts/package.sh

或推送后使用 GitHub Actions「Package macOS」工作流下载 .dmg 产物。
EOF
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "❌ 未找到 xcodebuild。请安装 Xcode 与 Command Line Tools。"
  exit 1
fi

mkdir -p "$DIST" "$DERIVED" "$ROOT/build"
find "$DIST" -mindepth 1 ! -name '.gitkeep' -exec rm -rf {} +
rm -rf "$DERIVED"

echo "==> 版本 ${VERSION} (${BUILD_NUMBER})"
echo "==> Bundle ID ${BUNDLE_ID}"

COMMON_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIG"
  -derivedDataPath "$DERIVED"
  MARKETING_VERSION="$VERSION"
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
)

if [[ "$SIGN" -eq 0 ]]; then
  COMMON_ARGS+=(
    CODE_SIGN_IDENTITY="-"
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGNING_REQUIRED=NO
    AD_HOC_CODE_SIGNING_ALLOWED=YES
  )
else
  if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')"
    if [[ -z "$IDENTITY" ]]; then
      IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Mac Developer/{print $2; exit}')"
    fi
  fi
  if [[ -z "$IDENTITY" ]]; then
    echo "❌ 未找到可用的代码签名证书。"
    echo "   请在 Xcode → Settings → Accounts 下载证书，或传入："
    echo "   --identity \"Developer ID Application: Your Name (TEAMID)\""
    exit 1
  fi
  echo "==> 签名身份: $IDENTITY"
  COMMON_ARGS+=(CODE_SIGN_IDENTITY="$IDENTITY")
  if [[ -n "$TEAM_ID" ]]; then
    COMMON_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
  fi
fi

if [[ "$APP_STORE" -eq 1 ]]; then
  echo "==> Archive for App Store…"
  xcodebuild archive \
    "${COMMON_ARGS[@]}" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS"

  EXPORT_OPTS="$ROOT/scripts/ExportOptions-AppStore.plist"
  EXPORT_DIR="$DIST/AppStore"
  mkdir -p "$EXPORT_DIR"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTS"
  echo "✅ App Store 导出完成: $EXPORT_DIR"
  ls -la "$EXPORT_DIR"
  exit 0
fi

echo "==> Build Release…"
set +e
xcodebuild build \
  "${COMMON_ARGS[@]}" \
  -destination "platform=macOS" \
  2>&1 | tee "$ROOT/build/xcodebuild.log"
BUILD_STATUS=${PIPESTATUS[0]}
set -e
if [[ "$BUILD_STATUS" -ne 0 ]]; then
  echo "❌ 编译失败，日志: $ROOT/build/xcodebuild.log"
  exit "$BUILD_STATUS"
fi

APP_SRC="$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 1 -name "${APP_NAME}.app" -print -quit || true)"
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "❌ 未找到 ${APP_NAME}.app。完整日志: $ROOT/build/xcodebuild.log"
  exit 1
fi

APP_DST="$DIST/${APP_NAME}.app"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"

ENTITLEMENTS="$ROOT/Paste/Paste/Paste.entitlements"
if [[ "$SIGN" -eq 1 ]]; then
  echo "==> 深度签名 .app…"
  if [[ -f "$ENTITLEMENTS" ]]; then
    codesign --force --deep --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$IDENTITY" \
      "$APP_DST"
  else
    codesign --force --deep --options runtime --sign "$IDENTITY" "$APP_DST"
  fi
  codesign --verify --deep --strict --verbose=2 "$APP_DST"
fi

# --- DMG ---
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST/$DMG_NAME"
STAGE="$ROOT/build/dmg-stage"
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "$STAGE"
cp -R "$APP_DST" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"

echo "==> 创建 DMG: $DMG_NAME"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG_PATH"

if [[ "$SIGN" -eq 1 ]]; then
  codesign --force --sign "$IDENTITY" "$DMG_PATH" || true
fi

PKG_PATH=""
if [[ "$MAKE_PKG" -eq 1 ]]; then
  PKG_NAME="${APP_NAME}-${VERSION}.pkg"
  PKG_PATH="$DIST/$PKG_NAME"
  COMPONENT_PKG="$ROOT/build/${APP_NAME}-component.pkg"
  echo "==> 创建 PKG: $PKG_NAME"
  pkgbuild \
    --install-location "/Applications" \
    --component "$APP_DST" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    "$COMPONENT_PKG"

  if [[ "$SIGN" -eq 1 ]]; then
    INSTALLER_ID="$(security find-identity -v -p basic 2>/dev/null | awk -F'"' '/Developer ID Installer/{print $2; exit}')"
    if [[ -n "$INSTALLER_ID" ]]; then
      productbuild --package "$COMPONENT_PKG" --sign "$INSTALLER_ID" "$PKG_PATH"
    else
      echo "⚠️ 未找到 Developer ID Installer 证书，输出未签名 pkg"
      cp "$COMPONENT_PKG" "$PKG_PATH"
    fi
  else
    cp "$COMPONENT_PKG" "$PKG_PATH"
  fi
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  echo "==> 公证 DMG（notarytool profile: $NOTARY_PROFILE）…"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  if [[ -n "$PKG_PATH" && -f "$PKG_PATH" ]]; then
    xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait || true
  fi
fi

(
  cd "$DIST"
  {
    shasum -a 256 "$DMG_NAME"
    [[ -n "$PKG_PATH" && -f "$(basename "$PKG_PATH")" ]] && shasum -a 256 "$(basename "$PKG_PATH")"
  } > SHA256.txt
)

echo
echo "✅ 打包完成"
echo "  App : $APP_DST"
echo "  DMG : $DMG_PATH"
[[ -n "$PKG_PATH" ]] && echo "  PKG : $PKG_PATH"
echo
echo "安装方式："
echo "  1. 打开 $DMG_NAME"
echo "  2. 将 Paste 拖到 Applications"
echo "  3. 未公证时：系统设置 → 隐私与安全性 → 仍要打开"
