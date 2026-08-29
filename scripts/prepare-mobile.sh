#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_BUILD_DIR="${1:-$PROJECT_ROOT/mobile_build}"

flutter create \
  --platforms=android,ios \
  --org dev.rimbakawal \
  --project-name rimbakawal \
  "$MOBILE_BUILD_DIR"

cp -R "$PROJECT_ROOT/lib/." "$MOBILE_BUILD_DIR/lib/"
cp -R "$PROJECT_ROOT/assets" "$MOBILE_BUILD_DIR/assets"
cp "$PROJECT_ROOT/pubspec.yaml" "$MOBILE_BUILD_DIR/pubspec.yaml"
cp "$PROJECT_ROOT/mobile/android/AndroidManifest.xml" \
  "$MOBILE_BUILD_DIR/android/app/src/main/AndroidManifest.xml"
cp "$PROJECT_ROOT/mobile/ios/Info.plist" \
  "$MOBILE_BUILD_DIR/ios/Runner/Info.plist"
cp "$PROJECT_ROOT/mobile/ios/Runner.entitlements" \
  "$MOBILE_BUILD_DIR/ios/Runner/Runner.entitlements"

perl -0pi -e \
  's/(PRODUCT_BUNDLE_IDENTIFIER = dev\.rimbakawal\.rimbakawal;)/$1\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner\/Runner.entitlements;/g' \
  "$MOBILE_BUILD_DIR/ios/Runner.xcodeproj/project.pbxproj"

cd "$MOBILE_BUILD_DIR"
flutter pub get
dart run flutter_launcher_icons
