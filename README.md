# RimbaKawal Patrol NFC — Phase 1A

First runnable mobile prototype for the patrol/checkpoint system.

## What works now

- One Flutter mobile codebase for Android + iOS
- Real NFC scanning through `nfc_manager 4.2.1`
- ISO 14443 polling (the family used by NTAG215)
- Android tag UID/identifier capture
- iOS identifier capture for MiFare / ISO7816 / ISO15693 tags when exposed by Core NFC
- Touch 'n Go card can be used as a temporary **detection/UID test tag** on a compatible Android NFC phone
- In-memory scan history
- Mock NFC mode for development without a physical tag
- NFC code remains isolated behind `NfcService`

## Important scope

The prototype only **detects/identifies** a Touch 'n Go card. It does not read balance, payment data, secret keys, or modify the card.

For the real checkpoint system, use the NTAG215 tags you ordered and treat each tag UID as the checkpoint identifier.

## Windows setup

Requirements:

1. Flutter stable with Dart >= 3.11
2. Android Studio / Android SDK
3. An NFC-capable Android phone
4. USB debugging enabled on the phone

From PowerShell, inside this starter folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup_windows.ps1
```

Then:

```powershell
cd patrol_nfc
flutter devices
flutter run
```

The setup script automatically adds this Android configuration:

```xml
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="false" />
```

## Test with your Touch 'n Go card

1. Enable NFC on the Android phone.
2. Launch the app with `flutter run`.
3. Tap **Scan checkpoint**.
4. Hold the Touch 'n Go card against the phone's NFC antenna area.
5. The app should show a UID such as `04:AA:BB:CC:DD:EE:FF` and the Android NFC technologies detected.

This validates the app → NFC hardware → tag detection path before the NTAG215 arrives.

## Mock mode

```powershell
flutter run --dart-define=USE_MOCK_NFC=true
```

## iOS later

The Dart code is already structured for iOS NFC, but an iOS build still requires Apple's normal signing/Xcode process on macOS. Before building for iPhone, configure:

- Near Field Communication Tag Reading capability/entitlement
- `NFCReaderUsageDescription` in `Info.plist`

You can continue building nearly all Flutter UI/business/API code on Windows in the meantime.

## Architecture

```text
PatrolScreen
    |
    v
NfcService
    |
    +-- RealNfcService  <-- default
    |      |
    |      +-- Android NfcTagAndroid.id
    |      +-- iOS MiFare/Iso identifiers
    |
    +-- MockNfcService  <-- --dart-define=USE_MOCK_NFC=true
```

## Next build milestone

After confirming one real NFC scan:

```text
Mobile
  Scan tag
    -> identify checkpoint
    -> capture timestamp
    -> capture patrol/officer/device
    -> queue locally if offline
    -> POST scan to API

API / database
  users
  devices
  checkpoints
  patrol_sessions
  scans

Web dashboard
  checkpoint setup
  patrol history
  missed checkpoints
  officer/session review
  export/reporting
```
