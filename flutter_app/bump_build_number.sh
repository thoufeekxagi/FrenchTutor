#!/bin/bash
# Auto-increments the iOS build number using the total git commit count — always
# strictly increasing, never needs manual tracking, never collides. Run this once,
# right before opening Xcode to Archive. See BUILD_FLUTTER_TO_IPHONE.md.
set -euo pipefail
cd "$(dirname "$0")"

NEXT_BUILD=$(git rev-list --count HEAD)
NEXT_BUILD=$((NEXT_BUILD + 1)) # +1 for the commit this bump itself will become

CURRENT=$(grep '^version:' pubspec.yaml | sed -E 's/^version: [0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)$/\1/')
if [ "$NEXT_BUILD" -le "$CURRENT" ]; then
  echo "Build number already at $CURRENT (>= computed $NEXT_BUILD) — nothing to do."
  exit 0
fi

sed -i '' -E "s/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+/version: \1+$NEXT_BUILD/" pubspec.yaml
echo "Bumped build number: $CURRENT -> $NEXT_BUILD"

# Regenerate Xcode's Generated.xcconfig from the new pubspec so Archive picks it up.
flutter pub get >/dev/null
echo "Ready to Archive in Xcode."
