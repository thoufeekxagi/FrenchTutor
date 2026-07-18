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

# `flutter pub get` alone does NOT reliably regenerate Generated.xcconfig (it only
# updates it as a side effect of resolving NEW dependencies) — this bit us: pubspec.yaml
# said +57 while Xcode kept archiving build 2. `flutter build ios --config-only` is the
# command that actually forces Xcode's config to be rewritten, and unlike a real build
# it takes seconds, not minutes.
flutter build ios --config-only >/dev/null
ACTUAL=$(grep '^FLUTTER_BUILD_NUMBER=' ios/Flutter/Generated.xcconfig | cut -d= -f2)
if [ "$ACTUAL" != "$NEXT_BUILD" ]; then
  echo "ERROR: Generated.xcconfig shows build $ACTUAL, expected $NEXT_BUILD — do not archive yet." >&2
  exit 1
fi
echo "Generated.xcconfig confirmed at build $ACTUAL. Ready to Archive in Xcode."
