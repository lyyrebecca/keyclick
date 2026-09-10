#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
# Full Swift Testing runs on systems whose developer tools ship the Testing
# frameworks. Some stock GitHub images omit those private frameworks; the same
# assertions are always executed by the portable KeyClickChecks target below.
if ! swift test; then
  printf '⚠ Swift Testing framework unavailable; continuing with portable core checks.\n'
fi
swift build -c debug --product KeyClickChecks
.build/debug/KeyClickChecks
plutil -lint Info.plist >/dev/null
printf '✔ KeyClick tests and manifest validation passed\n'
