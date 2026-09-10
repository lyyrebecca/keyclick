#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
swift test
swift build -c debug --product KeyClickChecks
.build/debug/KeyClickChecks
plutil -lint Info.plist >/dev/null
printf '✔ KeyClick tests and manifest validation passed\n'
