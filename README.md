# ZPatrol

**ZPatrol** is an offline-first security guard patrol, attendance, checkpoint, live monitoring and reporting platform built with Flutter and Cloudflare.

It is designed for real security operations in schools and other managed sites. Guards can continue core patrol duties when Internet connectivity is unreliable, while centralized features such as attendance verification, company administration, multi-site monitoring and reporting remain cloud-managed.

> **Current application version:** `0.8.1+42`  
> **Status:** Active production development  
> **Production web:** https://zpatrol.fscapitalmanagement.workers.dev

## What ZPatrol does

ZPatrol combines the operational functions normally spread across a watchman clock, attendance system, patrol logbook, incident channel and management dashboard into one platform:

- NFC-based guard patrol checkpoints
- offline-first patrol operation with automatic synchronization
- live GPS patrol monitoring
- geofenced attendance with live selfie capture
- AI-assisted attendance image verification and Management review
- company, school/site, user and checkpoint administration
- multi-school company hierarchy and company-level administration
- incidents, SOS and welfare workflows
- Command Center / Pusat Pemantauan
- patrol and attendance history with audit records
- monthly operational reporting
- BPPA PKK 2 attendance reports
- BPPA PKK 3 watchman-clock reports
- Flutter web, Android and iOS codebase
- Cloudflare Workers + D1 backend
- GitHub Actions CI/CD for production deployment and mobile builds

## Latest architecture: Company -> School -> Operations

ZPatrol now treats **Company / Syarikat** as a first-class entity instead of storing a company name as free text inside each school record.

```text
Company / Syarikat
    |
    +-- Administration users
    |
    +-- School / Site A
    |      +-- Patrol users
    |      +-- Supervisor users
    |      +-- Checkpoints
    |      +-- Attendance geofence
    |
    +-- School / Site B
    |      +-- Patrol users
    |      +-- Supervisor users
    |      +-- Checkpoints
    |      +-- Attendance geofence
    |
    +-- School / Site C ...
```

This structure allows one security company to manage multiple schools or operational sites without duplicating company data.

### Company management

Management can:

- create and maintain Company records
- activate or deactivate a Company
- view how many schools are linked to a Company
- view how many Administration users are linked to a Company
- assign a school/site to an official Company record
- assign Administration users at Company level
- keep Patrol and Supervisor users scoped to their operational school/site

The deployment pipeline also verifies that production data remains aligned to the Company hierarchy after database migrations.

### Multi-school administration

Company-level Administration is designed to support operations across multiple schools/sites belonging to the same Company. This enables centralized oversight while keeping patrol users, checkpoints, attendance boundaries and operational records scoped to the correct location.

Reports and administrative workflows can therefore operate across the Company's schools instead of assuming one administrator belongs to only one school.

## Core design principles

- **Offline-first patrol operation** - checkpoint duties should not stop because Internet access is unavailable.
- **Local write first** - supported field events are persisted locally before synchronization.
- **Automatic synchronization** - normal guards are not expected to operate a manual sync queue.
- **Server-side validation** - sensitive rules are enforced by the backend, not only by hidden Flutter controls.
- **Role-aware access** - Patrol, Supervisor, Administration and Management capabilities are separated.
- **Auditable operations** - patrol, attendance, incident and administrative actions are stored as records.
- **Real-time where necessary** - live patrol GPS and cloud attendance verification use connectivity when available.
- **Multi-site ready** - the Company hierarchy supports one company managing multiple schools or sites.

## 1. Guard patrol operations

- Start and end **Sesi Rondaan**.
- Scan physical NFC checkpoints using `nfc_manager`.
- Designed for NTAG-compatible NFC checkpoint tags.
- Validate checkpoint UIDs against the authenticated user's assigned school/site.
- Support configured checkpoint ordering.
- Show checkpoint progress during an active patrol.
- Display checkpoint/job instructions.
- Record patrol start time, completion time and route trail.
- Record which guard scanned each checkpoint.
- View patrol history by session.
- Allow authorized Management users to delete a patrol session from **Sejarah Rondaan**.
- Provide a flashlight shortcut during active patrols.
- Record incidents, SOS events and welfare actions.

## 2. Offline-first patrol data flow

Field patrol activity does not depend on a successful HTTP request for every action.

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

Queued events use unique identifiers so synchronization retries can be handled safely and duplicate cloud records can be reduced.

## 3. Automatic synchronization

The client can attempt synchronization:

- when the application starts
- when connectivity returns
- periodically while the application is running
- when the application resumes
- after new local events are created
- before logout when possible

Management can inspect synchronization health while normal patrol users are not required to manage a Sync Center.

## 4. Attendance / Kehadiran

ZPatrol includes a punch-card style attendance system tied to the configured location of each school/site.

### Attendance workflow

1. Management configures the site's attendance point and permitted radius.
2. The user opens **Kehadiran**.
3. The application requests the current geolocation.
4. The user captures a live selfie.
5. The backend verifies that the device is inside the configured attendance radius.
6. The attendance event is stored as `IN` or `OUT`.
7. Management reviews attendance history and supporting evidence when needed.

### Web attendance

The production web application supports:

- browser geolocation permission
- webcam permission
- live webcam preview
- front-facing/user-facing camera preference when supported
- selfie capture before punch submission

### Mobile attendance

Mobile builds use the device camera and high-accuracy location services for attendance capture.

### Attendance evidence and validation

Attendance records can include:

- Punch Masuk / Punch Keluar
- timestamp
- latitude and longitude
- GPS accuracy
- distance from the configured attendance point
- live selfie
- registered profile picture reference
- AI-assisted face-verification status and score when available
- Management review status
- reviewer and review timestamp

Face comparison is an **AI-assisted verification signal**, not an infallible biometric identity system. Uncertain results can be escalated for Management review.

### Attendance review

Management can open **Sejarah Kehadiran** and inspect:

- registered profile image
- attendance selfie
- location evidence
- distance from the permitted area
- verification result
- verification score/reason when available
- review status

An authorized Management user can mark a record as **DISEMAK**. The reviewed state, reviewer and review timestamp are persisted in the backend.

## 5. School / site configuration

Management can maintain school/site settings including:

- school/site name
- linked Company
- patrol-session interval
- patrol-session start time
- active/inactive state
- attendance latitude/longitude
- attendance radius
- attendance location label
- Zon

The map in the school/site settings is used to define the attendance/geofence centre.

## 6. User administration

Management can create and edit users with data including:

- Name
- No. Kad Pengenalan
- No. PK
- Role / Jawatan
- Company or school assignment, depending on role
- Guard status where applicable
- profile picture

### Patrol

Typical capabilities:

- Mula Rondaan
- NFC checkpoint scanning
- attendance punch
- patrol progress
- incident reporting
- SOS / welfare actions
- patrol history
- profile

### Supervisor

Supervisor capabilities can include monitoring for the relevant school/site operational scope.

### Administration

Administration users can be associated with a **Company** rather than being restricted to a single school. This supports centralized multi-school administration for the Company's operational sites.

### Management

Management includes higher-level administrative and monitoring capabilities such as:

- Command Center / Pusat Pemantauan
- live patrol map
- attendance overview
- attendance history and review
- Company management
- user administration
- school/site administration
- checkpoint administration
- patrol-session deletion
- incident management
- report generation

Sensitive authorization is enforced by backend routes and does not rely only on Flutter UI visibility.

## 7. Live patrol GPS

When a patrol is active, ZPatrol can publish position updates to the cloud so authorized users can monitor patrol movement.

The system distinguishes patrol presence from GPS availability, allowing states such as:

- patrol active and waiting for GPS
- live location available
- delayed/stale location
- patrol ended

Location trail records can later be shown as part of patrol history.

> Continuous tracking after the operating system force-kills the application is not guaranteed by normal foreground location tracking.

## 8. Pusat Pemantauan / Command Center

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

## 9. Reports

The Management **Laporan** screen supports monthly report generation using **Bulan**, **Tahun** and operational scope such as school/site.

The latest Company hierarchy also supports administration and reporting across multiple schools managed by the same Company.

### ZPatrol monthly patrol report

Can include:

- active users
- checkpoint scans
- scan timestamps
- guard names
- school/site
- checkpoint names
- SOS records

### BPPA PKK 2 - Borang Kehadiran Pengawal

ZPatrol can generate the monthly **BPPA PKK 2 Borang Kehadiran Pengawal** using stored attendance data.

The report can use operational metadata for:

- Nama Pengawal
- No. PK
- Waktu Masuk
- Waktu Keluar
- Nama Syarikat
- Zon
- Syif

Shift is derived automatically from Malaysian punch time:

- **1 - SIANG:** `07:00` to `18:59`
- **2 - MALAM:** `19:00` to `06:59`

### BPPA PKK 3 - Laporan Pelaksanaan Kunci Jam

ZPatrol can generate **BPPA PKK 3 Laporan Pelaksanaan Kunci Jam / Watchman Clock** reports by month.

The report:

- generates weekly pages across the selected month
- fills Company and Zon data from the configured hierarchy
- groups checkpoint activity by date
- arranges checkpoint entries according to patrol session and checkpoint position
- displays checkpoint times using recorded operational data

## 10. NFC architecture

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

## Backend responsibilities

The Worker API handles responsibilities including:

- authentication and session validation
- role/permission authorization
- Company CRUD and Company-user relationships
- school/site-to-Company relationships
- patrol bootstrap/configuration
- NFC checkpoint validation
- route-order validation
- offline-event synchronization
- patrol history
- patrol trails
- attendance geofence validation
- attendance evidence storage
- attendance review
- school/site configuration
- user profile metadata
- incidents
- SOS
- welfare events
- live patrol presence
- live location trail
- Command Center data
- multi-site Administration scope
- monthly reports
- BPPA report data
- administrative CRUD operations

## Data integrity model

ZPatrol intentionally avoids trusting the mobile UI for security-sensitive decisions.

Examples:

- an NFC UID must belong to an active checkpoint
- the checkpoint must belong to the authenticated user's school/site
- route requirements can be validated server-side
- privileged endpoints validate permission server-side
- attendance punches are checked against the configured geofence radius
- attendance GPS accuracy is validated by the backend
- attendance review state is persisted on the server
- patrol-session deletion is restricted to authorized users
- synchronization identifiers make retries safer
- school/site records are linked to official Company records
- Company Administration scope is represented explicitly in the data model

## Authentication

The current application supports **No. Kad Pengenalan** based login as specified by the project.

Potential future production enhancements include:

- PIN/password in addition to identity number
- passkeys
- MFA for privileged users
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
  --dart-define=API_BASE_URL=https://zpatrol.fscapitalmanagement.workers.dev
```

PowerShell:

```powershell
flutter run -d chrome --dart-define=USE_MOCK_NFC=true --dart-define=API_BASE_URL=https://zpatrol.fscapitalmanagement.workers.dev
```

### Run Android with real NFC

```bash
flutter run \
  --dart-define=USE_MOCK_NFC=false \
  --dart-define=API_BASE_URL=https://zpatrol.fscapitalmanagement.workers.dev
```

## Production builds

### Android APK

```bash
flutter build apk --release \
  --dart-define=USE_MOCK_NFC=false \
  --dart-define=API_BASE_URL=https://zpatrol.fscapitalmanagement.workers.dev
```

### Android App Bundle

```bash
flutter build appbundle --release \
  --dart-define=USE_MOCK_NFC=false \
  --dart-define=API_BASE_URL=https://zpatrol.fscapitalmanagement.workers.dev
```

### iOS

A normal installable iPhone build requires Apple code signing, an appropriate provisioning profile and Xcode on macOS.

GitHub Actions can compile an unsigned iOS build for validation, but an unsigned `.app` is not equivalent to a signed App Store/device build.

## Cloudflare deployment

Production deployment is automated through GitHub Actions after changes reach `main`.

The pipeline includes:

1. `flutter pub get`
2. `flutter analyze`
3. Flutter web release build
4. web service-worker/static asset preparation
5. pinned Wrangler setup
6. D1 database resolution
7. D1 migrations and Company hierarchy alignment
8. production data hierarchy verification
9. Worker + static asset deployment

D1 migrations:

```text
migrations/
```

Worker code:

```text
worker/
```

## Mobile CI

The repository contains GitHub Actions automation for production mobile compilation, including Android release builds and unsigned iOS build validation.

## Project structure

```text
lib/
  core/
    api/              API client and models
    nfc/              NFC abstraction and implementations
    offline/          local storage, session vault and auto-sync

  features/
    admin/            Company, school, user, reports and Command Center
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
- more advanced workforce scheduling
- configurable notifications and escalation rules
- richer analytics and trend reports
- additional attendance exception workflows
- immutable configuration snapshots for long-term audit requirements

## Security and privacy

This repository is public.

Do not commit:

- real identity-card numbers
- passwords or session tokens
- Cloudflare API credentials
- private staff photos
- attendance selfies
- sensitive incident reports
- private GPS/location trails

Production user, patrol, attendance, incident and location data should remain in runtime storage/services rather than source control.

## Product direction

ZPatrol is evolving from a simple checkpoint reader into a broader **multi-site guard operations platform**:

```text
Company / multi-school administration
        +
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

The operating principle remains simple: **guards should be able to perform core patrol duties even when connectivity is unreliable, while authorized administrators retain a centralized, auditable view across the Company's managed sites whenever the cloud is available.**
