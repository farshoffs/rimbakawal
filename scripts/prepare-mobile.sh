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

mkdir -p "$MOBILE_BUILD_DIR/android/app/src/main/kotlin/dev/rimbakawal/rimbakawal"
mkdir -p "$MOBILE_BUILD_DIR/android/app/src/main/res/raw"
cp "$PROJECT_ROOT/mobile/android/MainActivity.kt" \
  "$MOBILE_BUILD_DIR/android/app/src/main/kotlin/dev/rimbakawal/rimbakawal/MainActivity.kt"
cp "$PROJECT_ROOT/mobile/ios/AppDelegate.swift" \
  "$MOBILE_BUILD_DIR/ios/Runner/AppDelegate.swift"

python3 - "$PROJECT_ROOT/assets/audio/patrol_alarm.wav" \
  "$MOBILE_BUILD_DIR/android/app/src/main/res/raw/rondaan_reminder.wav" <<'PYWAV'
import math
import sys
import wave

source, output = sys.argv[1:3]
with wave.open(source, 'rb') as reader:
    params = reader.getparams()
    frames = reader.readframes(reader.getnframes())
    source_frames = reader.getnframes()

if source_frames <= 0 or not frames:
    raise SystemExit('patrol_alarm.wav contains no audio frames')

target_frames = params.framerate * 30
repeats = math.ceil(target_frames / source_frames)
bytes_per_frame = params.nchannels * params.sampwidth
payload = (frames * repeats)[: target_frames * bytes_per_frame]

with wave.open(output, 'wb') as writer:
    writer.setparams(params)
    writer.writeframes(payload)
PYWAV
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
