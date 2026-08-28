#!/usr/bin/env bash
set -euo pipefail

FLUTTER_HOME="${FLUTTER_HOME:-$PWD/.flutter-sdk}"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  echo "Flutter SDK not found in Cloudflare build image; installing stable Flutter..."
  rm -rf "$FLUTTER_HOME"
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

flutter config --enable-web --no-analytics
flutter --version
flutter pub get
flutter build web --release --dart-define=USE_MOCK_NFC=true

test -f build/web/index.html

echo "RimbaKawal Flutter web build ready at build/web"
