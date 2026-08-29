# RimbaKawal

**RimbaKawal** is an offline-first smart guard patrol and checkpoint management platform built with Flutter and Cloudflare.

It is designed for real field operations where mobile connectivity cannot be trusted. Patrol data is written to the device first and synchronized automatically when connectivity is available, while live patrol GPS remains a real-time cloud feature.

> Current status: active production development.

## Core principles

- **Offline first** — patrol operations must continue without Internet access.
- **Local write first** — operational events are saved on the device before cloud synchronization.
- **Automatic synchronization** — there is no manual Sync Center for normal users.
- **Server-side validation** — checkpoint, department and ordered-route rules are enforced by the backend.
- **Real-time location only where needed** — live patrol GPS is intentionally sent directly to the cloud while a patrol is active.
- **Role-aware UI** — operational staff see only what they need; Management gets monitoring and administration tools.

## What RimbaKawal can do

### Patrol operations

- Start and end patrol sessions.
- Scan physical NFC checkpoints using `nfc_manager`.
- Designed for NTAG215 checkpoint tags.
- Validate checkpoint UIDs locally using cached patrol configuration.
- Preserve the original event timestamp and available location data.
- Enforce ordered checkpoint routes when enabled.
- Prevent duplicate checkpoint completion within the same patrol session.
- Show patrol progress and the next required checkpoint.
- Display checkpoint/job instructions.
- Record incidents from the field.
- Record SOS events locally before synchronization.
- Welfare / `Saya OK` style patrol checks.

### Offline-first data flow

Field events are not dependent on a successful HTTP request.

```text
Patrol action
    |
    v
Local persistent store
    |
    +--> UI immediately continues
    |
    +--> Pending event queue
            |
            v
       Automatic sync engine
            |
            +--> Internet unavailable -> keep locally
            |
            +--> Internet available -> send to Cloudflare API
                                         |
                                         v
                                   D1 / cloud records
```

Examples of local-first events include:

- checkpoint scans
- patrol start/end
- incidents
- SOS records
- welfare checks

Each queued event uses a unique identifier so synchronization retries can be processed idempotently and avoid normal duplicate cloud records.

### Automatic synchronization

Synchronization is deliberately automatic rather than user-controlled.

The client attempts synchronization:

- when the application starts
- when network connectivity returns
- periodically while the application is running
- when the application resumes
- after new local events are created
- before logout when possible

Patrol users do **not** see pending/sync/failed counters or a manual retry screen.

Only **Management** can see a small read-only synchronization indicator such as:

- `AUTO SYNC • READY`
- `AUTO SYNC • SYNCING`
- `AUTO SYNC • 3 PENDING`
- the most recent synchronization time

There is no manual Sync Center in the current product design.

## Live patrol GPS

Live GPS is the main exception to the local-first synchronization rule.

When a patrol is active, RimbaKawal publishes location updates to the cloud so Management can monitor patrol movement on the live map.

The live monitoring model separates **patrol presence** from **GPS availability**. This means the system can distinguish between:

- patrol active, waiting for a GPS fix
- live location available
- delayed location
- stale location
- patrol ended

Location trails can be displayed on the monitoring map when position updates are available.

> Live GPS depends on device location permission, operating-system restrictions and connectivity. Reliable tracking after the application is force-killed requires additional native background-location work and should not be assumed from foreground tracking alone.

## Management Command Center

Management users have access to an operational monitoring dashboard that includes:

- active patrol users
- checkpoint completion progress
- current patrol/session state
- completed / patrolling / late / missed status
- latest checkpoint activity
- unresolved incidents
- urgent incidents
- recent SOS records
- live patrol map access
- auto-refreshing operational information

The goal is to make the monitoring screen an operations console rather than a static history page.

## Roles

### Patrol

Typical access:

- Mula Rondaan
- NFC checkpoint scanning
- patrol progress
- incident reporting
- SOS / welfare actions
- patrol history
- profile

Synchronization happens silently in the background.

### Management

Includes Patrol functionality where applicable plus:

- Command Center
- live patrol monitoring
- read-only sync health/status
- user administration
- Jabatan management
- checkpoint management
- reports
- incident acknowledgement/resolution
- system configuration

Sensitive authorization is enforced server-side and must not rely only on hidden Flutter buttons.

## NFC architecture

```text
PatrolScreen
    |
    v
NfcService
    |
    +-- RealNfcService
    |      |
    |      +-- Android NFC identifier
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
- Hive CE local persistent storage
- secure local session storage
- `connectivity_plus`
- `audioplayers`

### Cloud

- Cloudflare Workers
- Cloudflare Workers Static Assets
- Cloudflare D1
- REST API under `/api/*`
- GitHub Actions for automated deployment

### Production web

The current production web application is deployed at:

**https://rimbakawal.fscapitalmanagement.workers.dev**

## Backend responsibilities

The Worker API handles responsibilities including:

- authentication/session validation
- Management authorization
- patrol bootstrap/configuration
- NFC checkpoint validation
- ordered-route enforcement
- offline event synchronization
- idempotent sync receipts
- patrol history
- incidents
- SOS
- welfare events
- live patrol presence
- live location trail
- Command Center data
- reports
- administrative CRUD operations

## Data integrity model

RimbaKawal intentionally avoids trusting the mobile UI for security-sensitive decisions.

Examples:

- an NFC UID must belong to an active checkpoint
- the checkpoint must belong to the authenticated user's Jabatan
- ordered routes are validated by the backend
- duplicate scans within a session can be rejected
- Management endpoints validate Management permission server-side
- offline sync event identifiers are used to make retries safe

## Authentication

The current application supports identity-card-number based authentication as requested by the project specification.

For a hardened production deployment, stronger authentication should be considered, for example:

- PIN/password in addition to identity number
- passkeys
- MFA for Management
- login throttling / failed-attempt protection
- device registration where appropriate

Never commit real identity-card numbers, passwords, private profile pictures, API tokens or production credentials to this public repository.

## Local development

### Requirements

- Flutter stable
- Dart compatible with the version declared in `pubspec.yaml`
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

PowerShell example:

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

Unsigned CI compilation can verify that the iOS project builds, but an unsigned `.app` is not equivalent to a directly installable production iPhone application.

## Cloudflare deployment

Production deployment is automated through GitHub Actions.

The deployment pipeline performs operations such as:

1. `flutter pub get`
2. `flutter analyze`
3. Flutter web release build
4. install the pinned Wrangler version
5. resolve the D1 database
6. apply D1 migrations
7. deploy the Worker and static assets

D1 migrations live under:

```text
migrations/
```

Worker code lives under:

```text
worker/
```

## Project structure

```text
lib/
  core/
    api/              API client and models
    nfc/              NFC abstraction and implementations
    offline/          local ledger, session vault and auto-sync engine

  features/
    admin/            Management and Command Center
    auth/             login
    dashboard/        primary role-aware dashboard
    history/          patrol/clocking history
    patrol/           field patrol workflow
    profile/          user profile

worker/               Cloudflare Worker API
migrations/           Cloudflare D1 migrations
.github/workflows/    deployment and mobile build automation
```

## Current limitations / planned improvements

The following should not yet be treated as complete production capabilities:

- continuous background GPS after the app is force-killed
- full checkpoint geofencing enforcement
- virtual / beacon checkpoints
- configurable mobile form builder
- advanced route and shift scheduling
- immutable route/configuration snapshots for long-term audit history
- push notifications when Management devices are closed
- R2-backed profile/photo storage at larger scale
- stronger authentication such as PIN/passkeys/MFA

These are natural next steps as RimbaKawal moves from a patrol application into a broader patrol operations platform.

## Security and privacy

This repository is public.

Do not commit:

- real identity-card numbers
- passwords or session tokens
- Cloudflare API credentials
- private staff photos
- real incident reports containing sensitive information
- private location logs

Production user, patrol, incident and location data should remain in runtime storage/services rather than source control.

## Product direction

RimbaKawal is evolving beyond a simple NFC patrol reader into an **offline-first patrol operations platform** combining:

```text
NFC checkpoints
      +
Offline field operations
      +
Automatic cloud synchronization
      +
Live GPS monitoring
      +
Incident / SOS / welfare workflows
      +
Management Command Center
      +
Reports and audit history
```

The operating principle is simple: **a patrol must still be able to do its job even when the Internet cannot.**
