#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/KeyClick.app"
BUILD_DIR=".build/universal"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCHS=(arm64 x86_64)

python3 - <<'PY'
from pathlib import Path
import shutil
for path in [Path('dist/KeyClick.app'), Path('.build/universal')]:
    if path.exists(): shutil.rmtree(path)
PY
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in "${ARCHS[@]}"; do
  DIR="$BUILD_DIR/$ARCH"
  mkdir -p "$DIR/modules"
  xcrun swiftc -O -whole-module-optimization -swift-version 6 \
    -sdk "$SDK" -target "${ARCH}-apple-macos14.0" \
    -emit-library -static -emit-module -module-name KeyClickCore \
    -emit-module-path "$DIR/modules/KeyClickCore.swiftmodule" \
    -o "$DIR/libKeyClickCore.a" Sources/KeyClickCore/*.swift
  xcrun swiftc -O -whole-module-optimization -swift-version 6 \
    -sdk "$SDK" -target "${ARCH}-apple-macos14.0" \
    -I "$DIR/modules" -L "$DIR" -lKeyClickCore \
    -o "$DIR/KeyClick" Sources/KeyClickApp/*.swift
done

lipo -create "$BUILD_DIR/arm64/KeyClick" "$BUILD_DIR/x86_64/KeyClick" -output "$APP/Contents/MacOS/KeyClick"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/KeyClick.icns "$APP/Contents/Resources/KeyClick.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# The app's locally ad-hoc signature is intentionally finalized before users
# grant macOS privacy permissions.  Do not mutate the installed bundle after
# it has been authorized, because macOS correctly treats that as a new build.
codesign --force --deep --sign - "$APP"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP"
ARCH_OUTPUT="$(lipo -archs "$APP/Contents/MacOS/KeyClick")"
[[ "$ARCH_OUTPUT" == *arm64* && "$ARCH_OUTPUT" == *x86_64* ]]
printf '✔ Universal App 已生成：%s (%s)\n' "$PWD/$APP" "$ARCH_OUTPUT"
