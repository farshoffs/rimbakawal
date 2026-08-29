# RimbaKawal

**RimbaKawal** is an offline-first guard patrol, attendance, checkpoint, monitoring and reporting platform built with Flutter and Cloudflare.

It is designed for real security operations in schools and other managed sites. Core patrol activity can continue when connectivity is unreliable, while cloud-backed features such as attendance verification, live patrol monitoring, administration and reporting remain centrally managed.

> **Status:** Active production development.

## Overview

RimbaKawal combines:

- NFC-based guard patrol checkpoints
- offline-first patrol operations
- automatic synchronization
- live patrol GPS monitoring
- geofenced attendance with selfie capture
- attendance review and audit records
- incident and SOS workflows
- department and checkpoint administration
- monthly operational reporting
- BPPA PKK 2 attendance reports
- BPPA PKK 3 watchman-clock reports
- Flutter web, Android and iOS codebase
- Cloudflare Workers + D1 backend

## Core principles

- **Offline first for patrol operations** — checkpoint activity should not stop simply because Internet access is unavailable.
- **Local write first** — supported field events are persisted locally before synchronization.
- **Automatic synchronization** — normal patrol users are not expected to manage a manual sync queue.
- **Server-side validation** — sensitive rules are enforced by the backend, not merely by hidden UI controls.
- **Role-aware access** — Patrol, Supervisor and Management users receive different capabilities.
- **Auditable operations** — patrol, attendance, incident and administrative data are stored as operational records.
- **Real-time features where required** — active patrol GPS and cloud attendance verification intentionally depend on connectivity.

## Main features

### 1. Guard patrol operations

- Start and end **Sesi Rondaan**.
- Scan physical NFC checkpoints using `nfc_manager`.
- Designed for NTAG-compatible NFC checkpoint tags.
- Validate checkpoint UIDs against the authenticated user's Jabatan.
- Support configured checkpoint ordering.
- Show checkpoint progress during an active patrol.
- Display checkpoint/job instructions.
- Track patrol start time, completion time and route trail.
- Record which guard scanned each checkpoint.
- View patrol history by session.
- Management can delete a patrol session from Sejarah Rondaan.
- Flashlight shortcut is available during active patrols.
- Record incidents, SOS events and welfare actions.

### 2. Offline-first patrol data flow

Field patrol activity is designed to avoid depending on a successful HTTP request for every action.

```text
Patrol action
    |
    v
Local persistent store
    |
    +--> UI continues immediately
    |
    +--> Pending event queue
            |
            v
       Automatic sync engine
            |
            +--> Offline -> retain locally
            |
            +--> Online  -> Cloudflare API
                              |
                              v
                         D1 / cloud data
```

Examples of local-first events include:

- checkpoint scans
- patrol start/end
- incidents
- SOS records
- welfare checks

Queued events use unique identifiers so synchronization retries can be processed safely and duplicate cloud records can be reduced.

### 3. Automatic synchronization

The client can attempt synchronization:

- when the application starts
- when network connectivity returns
- periodically while the application is running
- when the application resumes
- after new local events are created
- before logout when possible

Management can see synchronization health information, while normal patrol users are not required to operate a Sync Center.

## Attendance / Kehadiran

RimbaKawal includes a punch-card style attendance system tied to a configured Jabatan location.

### Attendance workflow

1. Management configures the Jabatan's attendance point and permitted radius.
2. The user opens **Kehadiran**.
3. The application requests current geolocation.
4. The user captures a live selfie.
5. The backend verifies that the device is inside the configured attendance radius.
6. The attendance event is stored as `IN` or `OUT`.
7. Management can review attendance history and supporting evidence.

### Web attendance

The production web application supports:

- browser geolocation permission
- webcam permission
- live webcam preview
- front-facing/user-facing camera preference when supported by the browser
- selfie capture before punch submission

### Mobile attendance

Mobile builds use the device camera and high-accuracy location services for attendance capture.

### Attendance validation

Attendance records can include:

- Punch Masuk / Punch Keluar
- timestamp
- latitude and longitude
- GPS accuracy
- distance from configured Jabatan attendance point
- live selfie
- registered profile-picture reference
- face-verification status and score when available
- Management review status
- reviewer and review time

Face comparison is an **AI-assisted verification signal**, not an infallible biometric identity system. Uncertain cases can be marked for Management review instead of being silently treated as confirmed.

### Attendance review

Management can open **Sejarah Kehadiran** and inspect:

- registered profile image
- attendance selfie
- location evidence
- distance from the permitted area
- verification result
- verification score/reason when available
- review status

A Management user can mark a record as **DISEMAK**. The reviewed state, reviewer and review timestamp are persisted in the backend.

## Jabatan configuration

Management can maintain Jabatan settings including:

- Jabatan name
- patrol-session interval
- patrol-session start time
- active/inactive state
- attendance latitude/longitude
- attendance radius
- attendance location label
- **Nama Syarikat**
- **Zon**

The map in Jabatan settings is used to define the attendance/geofence centre.

## User administration

Management can create and edit users with data including:

- Name
- No. Kad Pengenalan
- **No. PK**
- Role / Jawatan
- Jabatan
- profile picture

Supported role concepts include:

### Patrol

Typical access:

- Mula Rondaan
- NFC checkpoint scanning
- attendance punch
- patrol progress
- incident reporting
- SOS / welfare actions
- patrol history
- profile

### Supervisor

Supervisor access can include monitoring capabilities for the relevant operational scope.

### Management

Management includes administrative and monitoring capabilities such as:

- Command Center / Pusat Pemantauan
- live patrol map
- attendance overview
- attendance history and review
- user administration
- Jabatan administration
- checkpoint administration
- patrol-session deletion
- incident management
- report generation

Sensitive authorization is enforced by backend routes and should never rely only on Flutter UI visibility.

## Live patrol GPS

When a patrol is active, RimbaKawal can publish position updates to the cloud so authorized users can monitor patrol movement.

The system distinguishes patrol presence from GPS availability, allowing states such as:

- patrol active and waiting for GPS
- live location available
- delayed/stale location
- patrol ended

Location trail records can later be shown as part of the patrol history.

> Continuous tracking after the operating system force-kills the application is not guaranteed by normal foreground location tracking.

## Pusat Pemantauan / Command Center

The monitoring dashboard can include:

- active patrol users
- patrol/session state
- checkpoint completion progress
- completed / patrolling / late / missed indicators
- latest checkpoint activity
- live patrol location
- unresolved incidents
- urgent incidents
- SOS activity
- attendance summary
- recent attendance punches
- users currently punched in
- attendance records requiring review

The goal is to operate as a real monitoring console rather than a static history page.

## Reports

The Management **Laporan** screen supports monthly report generation using **Bulan**, **Tahun** and optional Jabatan selection.

### RimbaKawal monthly patrol report

Includes operational information such as:

- active users
- checkpoint scans
- scan timestamps
- guard names
- Jabatan
- checkpoint names
- SOS records

### BPPA PKK 2 — Borang Kehadiran Pengawal

RimbaKawal can generate the monthly **BPPA PKK 2 Borang Kehadiran Pengawal** using attendance data.

The report uses stored operational metadata for:

- Nama Pengawal
- No. PK
- Waktu Masuk
- Waktu Keluar
- Nama Syarikat
- Zon
- Syif

Shift is derived automatically from the Malaysian punch time:

- **1 — SIANG:** `07:00` to `18:59`
- **2 — MALAM:** `19:00` to `06:59`

The report remains structured according to the BPPA PKK 2 form layout used by the project.

### BPPA PKK 3 — Laporan Pelaksanaan Kunci Jam

RimbaKawal can generate **BPPA PKK 3 Laporan Pelaksanaan Kunci Jam / Watchman Clock** reports by month.

The report:

- generates weekly pages across the selected month
- fills Nama Syarikat and Zon from Jabatan settings
- groups checkpoint activity by date
- arranges checkpoint entries according to patrol session and checkpoint position
- displays `Checkpoint 1`, `Checkpoint 2`, `Checkpoint 3`, and subsequent checkpoints using recorded times

## NFC architecture

```text
PatrolScreen
    |
    v
NfcService
    |
    +-- RealNfcService
    |      |
    |      +-- Android NFC identifiers
    |      +-- iOS Core NFC identifiers when exposed
    |
    +-- MockNfcService
           |
           +-- development / web testing
```

Real mobile builds use:

```text
USE_MOCK_NFC=false
```

Web/development testing can use:

```text
USE_MOCK_NFC=true
```

## Technology stack

### Client

- Flutter
- Dart
- `nfc_manager`
- `geolocator`
- `flutter_map`
- `image_picker`
- Hive CE local persistent storage
- secure local session storage
- `connectivity_plus`
- `audioplayers`
- `printing` / `pdf` for report generation

### Cloud

- Cloudflare Workers
- Cloudflare Workers Static Assets
- Cloudflare D1
- Cloudflare Workers AI integration for assisted attendance image verification
- REST API under `/api/*`
- GitHub Actions for automated deployment

## Production web

Current production web application:

**https://rimbakawal.fscapitalmanagement.workers.dev**

## Backend responsibilities

The Worker API handles responsibilities including:

- authentication and session validation
- role/Management authorization
- patrol bootstrap/configuration
- NFC checkpoint validation
- route-order validation
- offline-event synchronization
- patrol history
- patrol trails
- attendance geofence validation
- attendance evidence storage
- attendance review
- department configuration
- user profile metadata
- incidents
- SOS
- welfare events
- live patrol presence
- live location trail
- Command Center data
- monthly reports
- BPPA report data
- administrative CRUD operations

## Data integrity model

RimbaKawal intentionally avoids trusting the mobile UI for security-sensitive decisions.

Examples:

- an NFC UID must belong to an active checkpoint
- the checkpoint must belong to the authenticated user's Jabatan
- route requirements can be validated server-side
- Management endpoints validate Management permission server-side
- attendance punches are checked against the configured Jabatan radius
- attendance GPS accuracy is validated by the backend
- attendance review state is persisted on the server
- patrol-session deletion is restricted to Management
- synchronization identifiers are used to make retries safer

## Authentication

The current application supports No. Kad Pengenalan based login as specified by the project.

For stronger future production security, possible enhancements include:

- PIN/password in addition to identity number
- passkeys
- MFA for Management
- login throttling
- device registration

Never commit real identity-card numbers, API tokens, production credentials, private profile pictures or sensitive operational records to this public repository.

## Local development

### Requirements

- Flutter stable
- compatible Dart SDK
- Android Studio / Android SDK for Android development
- NFC-capable Android hardware for real NFC testing
- macOS + Xcode for normal signed iOS device/App Store builds

Install dependencies:

```bash
flutter pub get
```

Analyze:

```bash
flutter analyze
```

### Run web with mock NFC

```bash
flutter run -d chrome \
  --dart-define=USE_MOCK_NFC=true \
  --dart-define=API_BASE_URL=https://rimbakawal.fscapitalmanagement.workers.dev
```

PowerShell:

```powershell
flutter run -d chrome --dart-define=USE_MOCK_NFC=true --dart-define=API_BASE_URL=https://rimbakawal.fscapitalmanagement.workers.dev
```

### Run Android with real NFC

```bash
flutter run \
  --dart-define=USE_MOCK_NFC=false \
  --dart-define=API_BASE_URL=https://rimbakawal.fscapitalmanagement.workers.dev
```

## Production builds

### Android APK

```bash
flutter build apk --release \
  --dart-define=USE_MOCK_NFC=false \
  --dart-define=API_BASE_URL=https://rimbakawal.fscapitalmanagement.workers.dev
```

### Android App Bundle

```bash
flutter build appbundle --release \
  --dart-define=USE_MOCK_NFC=false \
  --dart-define=API_BASE_URL=https://rimbakawal.fscapitalmanagement.workers.dev
```

### iOS

A normal installable iPhone build requires Apple code signing, an appropriate provisioning profile and Xcode on macOS.

GitHub Actions can compile an unsigned iOS build for validation, but an unsigned `.app` is not equivalent to a signed App Store/device build.

## Cloudflare deployment

Production deployment is automated through GitHub Actions after changes reach `main`.

The deployment pipeline performs operations including:

1. `flutter pub get`
2. `flutter analyze`
3. Flutter web release build
4. configure web service-worker assets
5. install the pinned Wrangler version
6. resolve the D1 database
7. apply D1 migrations
8. deploy the Worker and static assets

D1 migrations:

```text
migrations/
```

Worker code:

```text
worker/
```

## Mobile CI

The repository also contains GitHub Actions automation for production mobile compilation, including Android release builds and unsigned iOS build validation.

## Project structure

```text
lib/
  core/
    api/              API client and models
    nfc/              NFC abstraction and implementations
    offline/          local storage, session vault and auto-sync

  features/
    admin/            Management, reports and Command Center
    attendance/       geofenced attendance workflow
    auth/             login
    dashboard/        role-aware dashboard
    history/          patrol history
    patrol/           active patrol workflow
    profile/          user profile

worker/               Cloudflare Worker API
migrations/           Cloudflare D1 migrations
.github/workflows/    deployment and mobile CI
```

## Current limitations / future improvements

Areas that can still be expanded include:

- stronger authentication such as PIN/passkeys/MFA
- robust continuous background GPS after application termination
- larger-scale image storage such as Cloudflare R2
- more advanced patrol and workforce scheduling
- additional attendance rules and exception workflows
- richer analytics and trend reports
- configurable notifications
- immutable configuration snapshots for long-term audit requirements

## Security and privacy

This repository is public.

Do not commit:

- real identity-card numbers
- passwords or session tokens
- Cloudflare API credentials
- Firebase credentials
- private staff photos
- attendance selfies
- real incident reports containing sensitive information
- private GPS/location trails

Production user, patrol, attendance, incident and location data should remain in runtime storage/services rather than source control.

## Product direction

RimbaKawal is evolving from a simple checkpoint reader into a broader **guard operations platform**:

```text
NFC checkpoint patrol
        +
Offline field operations
        +
Automatic cloud synchronization
        +
Geofenced attendance
        +
Selfie verification / review
        +
Live GPS monitoring
        +
Incident / SOS workflows
        +
Management Command Center
        +
Monthly BPPA reporting
```

The operating principle remains simple: **guards should be able to perform core patrol duties even when connectivity is unreliable, while Management retains a clear operational record when the cloud is available.**
