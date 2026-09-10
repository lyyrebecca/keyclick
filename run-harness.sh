#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
APP="dist/KeyClickTestTarget.app"
python3 - <<'PY'
from pathlib import Path
import shutil
p = Path('dist/KeyClickTestTarget.app')
if p.exists(): shutil.rmtree(p)
(p / 'Contents' / 'MacOS').mkdir(parents=True)
PY
xcrun swiftc -O -parse-as-library -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macos14.0" -o "$APP/Contents/MacOS/ClickTargetHarness" Support/ClickTargetHarness.swift
cp Support/ClickTargetHarness-Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
open "$APP"
