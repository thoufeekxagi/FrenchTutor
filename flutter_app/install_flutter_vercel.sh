#!/usr/bin/env bash
# Vercel install step. Vercel's build image has no Flutter SDK, so fetch a
# pinned version rather than "latest": an unpinned SDK means a Flutter release
# can break a production deploy with no change on our side.
set -euo pipefail

FLUTTER_VERSION="3.44.4"   # keep in sync with the SDK this app is developed on

if [ -d "$HOME/flutter" ]; then
  echo "Flutter already present, skipping clone."
else
  echo "Cloning Flutter $FLUTTER_VERSION..."
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$HOME/flutter"
fi

export PATH="$HOME/flutter/bin:$PATH"
flutter --version
flutter config --enable-web
flutter pub get
