# ZPatrol

**ZPatrol** is an offline-first security guard operations platform for patrol, attendance, live monitoring, incident management and reporting. It is built with Flutter and Cloudflare for schools and other managed sites.

> **Current version:** `0.8.1+42`  
> **Production web:** https://zpatrol.fscapitalmanagement.workers.dev  
> **Status:** Active production development

## Core product

ZPatrol combines:

- NFC checkpoint patrols
- offline-first field operation with automatic synchronization
- live GPS patrol monitoring
- geofenced attendance with live selfie capture
- AI-assisted attendance image verification and Management review
- Company, school/site, user and checkpoint administration
- multi-school Company hierarchy
- incident, SOS and welfare workflows
- Command Center / Pusat Pemantauan
- patrol and attendance history with audit records
- monthly operational reporting
- PKK 2, PKK 3 and PKK 4 PDF generation
- Flutter web, Android and iOS codebase
- Cloudflare Workers + D1 backend
- GitHub Actions CI/CD

## Latest hierarchy: Company -> Schools -> Operations

ZPatrol now treats **Company / Syarikat** as a first-class entity.

```text
Admin Sistem / Management
        |
        v
Company / Syarikat
        |
        +-- Administration user(s)
        |
        +-- School / Site A
        |      +-- Supervisor
        |      +-- Patrol users
        |      +-- Checkpoints
        |      +-- Attendance geofence
        |
        +-- School / Site B
        |      +-- Supervisor
        |      +-- Patrol users
        |      +-- Checkpoints
        |      +-- Attendance geofence
        |
        +-- Additional schools / sites
```

A single security company can therefore manage multiple schools or operational sites without duplicating company data.

### Access model

| Role | Scope |
| --- | --- |
| `Management` | Full system access across companies and schools. |
| `Administration` | Company-level reporting for schools linked to the same Company. |
| `Supervisor` | Operational monitoring for the assigned school/site. |
| `Patrol` | Patrol, attendance and field workflows for the assigned school/site. |

Company-level Administration can select a school under the same Company and generate the authorized PKK reports. Backend checks validate that the requested school is actually linked to the user's Company.

## Guard patrol operations

- Start and end **Sesi Rondaan**.
- Scan physical NFC checkpoints using `nfc_manager`.
- Designed for NTAG-compatible NFC checkpoint tags.
- Validate checkpoint UID against the authenticated user's school/site.
- Support configured checkpoint ordering.
- Display checkpoint progress and job instructions.
- Record patrol start/end time, guard identity and checkpoint times.
- Record which guard scanned each checkpoint.
- Preserve patrol history by session.
- Allow authorized Management users to delete patrol sessions.
- Provide flashlight access during active patrols.
- Record incidents, SOS events and welfare actions.

## Offline-first patrol engine

Core field actions do not need to wait for a successful cloud request before the guard can continue.

```text
Field action
    |
    v
Local persistent store
    |
    +--> UI continues
    |
    +--> Pending event queue
            |
            v
       Automatic sync
            |
            +--> Offline: keep locally
            |
            +--> Online: Cloudflare API -> D1
```

Local-first events can include:

- checkpoint scans
- patrol start/end
- incidents
- SOS records
- welfare checks

Synchronization can be attempted when the app starts, connectivity returns, the app resumes, new events are created, periodically while running and before logout when possible.

## Attendance / Kehadiran

ZPatrol includes a geofenced punch-card attendance workflow.

1. Management configures the school's attendance coordinate and allowed radius.
2. The user opens **Kehadiran**.
3. The app requests current geolocation.
4. The user captures a live selfie.
5. The backend checks the location, distance and GPS accuracy.
6. The event is stored as `IN` or `OUT`.
7. Management can review the supporting evidence.

Attendance records can include:

- Punch Masuk / Punch Keluar
- timestamp
- latitude and longitude
- GPS accuracy
- distance from the allowed area
- live selfie
- registered profile image reference
- AI-assisted verification result/score when available
- Management review status
- reviewer and review time

AI-assisted face comparison is treated as a verification signal, not as an infallible biometric identity decision.

## Company and school administration

Management can maintain:

### Company

- Company name
- active/inactive state
- linked school count
- linked Administration count

### School / site

- school/site name
- linked Company
- patrol interval
- patrol start time
- active/inactive state
- attendance latitude/longitude
- attendance radius
- attendance location label
- Zon

### Users

User data can include:

- Name
- No. Kad Pengenalan
- No. PK
- Role / Jawatan
- Company or school assignment depending on role
- guard status where applicable
- profile picture

Only Management can perform sensitive administration such as account blocking/unblocking. Blocking a user invalidates active sessions on the backend.

## Live patrol GPS

During an active patrol, ZPatrol can publish location updates so authorized users can monitor the patrol.

Possible states include:

- patrol active, waiting for GPS
- live location available
- delayed/stale location
- patrol ended

Patrol trail data can later be referenced in operational history.

## Pusat Pemantauan / Command Center

The dashboard can show:

- active patrol users
- patrol/session state
- checkpoint completion progress
- completed / patrolling / late / missed indicators
- latest checkpoint activity
- live patrol location
- unresolved and urgent incidents
- SOS activity
- attendance summary
- recent punches
- users currently punched in
- attendance records requiring review

## Reports

The **Jana Laporan** workflow uses a selected school, month and year and generates PDFs from ZPatrol operational data.

### PKK 2

**Pengesahan bilangan pengawal dan rekod kehadiran.**

It is generated from stored attendance and contract-related metadata for the selected school.

### PKK 3

**Pengesahan kehadiran pengawal berdasarkan rekod kehadiran.**

It uses the same operational attendance source rather than requiring a separate manual attendance file.

### PKK 4

**Pengesahan pelaksanaan rondaan dan clocking.**

It uses checkpoint scan data and patrol sessions to build the required patrol/clocking record.

Company-level Administration can select any school linked to the same `company_id` and generate the permitted PKK 2, PKK 3 or PKK 4 report.

## NFC architecture

```text
PatrolScreen
    |
    v
NfcService
    |
    +-- RealNfcService
    |      +-- Android NFC identifiers
    |      +-- iOS Core NFC identifiers when exposed
    |
    +-- MockNfcService
           +-- web / development testing
```

Real mobile builds:

```text
USE_MOCK_NFC=false
```

Web/development testing:

```text
USE_MOCK_NFC=true
```

## Technology stack

### Client

- Flutter / Dart
- `nfc_manager`
- `geolocator`
- `flutter_map`
- `image_picker`
- Hive CE local persistent storage
- secure local session storage
- `connectivity_plus`
- `audioplayers`
- `printing` / `pdf`

### Cloud

- Cloudflare Workers
- Cloudflare Workers Static Assets
- Cloudflare D1
- Cloudflare Workers AI for assisted attendance image verification
- REST API under `/api/*`
- GitHub Actions for deployment and mobile compilation

## Data integrity model

Security-sensitive rules are enforced server-side. Examples include:

- NFC UID must belong to an active checkpoint.
- The checkpoint must belong to the authenticated user's school/site.
- Route requirements can be validated by the backend.
- Privileged endpoints check server-side permission.
- Attendance punches are checked against geofence radius and GPS accuracy.
- Attendance review state is stored on the server.
- Company Administration requests are restricted to schools linked to the same Company.
- Synchronization identifiers are used to make retries safer.

## Authentication

The current application supports No. Kad Pengenalan based login as specified by the project.

Potential future hardening includes PIN/password, passkeys, MFA for privileged users, login throttling and device registration.

## Local development

Requirements:

- Flutter stable
- compatible Dart SDK
- Android SDK for Android development
- NFC-capable Android device for real NFC testing
- macOS + Xcode for normal signed iOS builds

```bash
flutter pub get
flutter analyze
```

### Web with mock NFC

```bash
flutter run -d chrome \
  --dart-define=USE_MOCK_NFC=true \
  --dart-define=API_BASE_URL=https://zpatrol.fscapitalmanagement.workers.dev
```

### Android with real NFC

```bash
flutter run \
  --dart-define=USE_MOCK_NFC=false \
  --dart-define=API_BASE_URL=https://zpatrol.fscapitalmanagement.workers.dev
```

## Production build examples

```bash
flutter build apk --release \
  --dart-define=USE_MOCK_NFC=false \
  --dart-define=API_BASE_URL=https://zpatrol.fscapitalmanagement.workers.dev
```

```bash
flutter build appbundle --release \
  --dart-define=USE_MOCK_NFC=false \
  --dart-define=API_BASE_URL=https://zpatrol.fscapitalmanagement.workers.dev
```

A normal signed iOS install requires macOS, Xcode and Apple code signing.

## Cloudflare deployment

GitHub Actions deploys changes from `main` and performs operations including:

1. dependency installation
2. Flutter analysis
3. production web build
4. static asset preparation
5. D1 migration execution
6. Company hierarchy/data alignment verification
7. Worker and static asset deployment

Key locations:

```text
lib/                  Flutter application
worker/               Cloudflare Worker API
migrations/           D1 migrations
docs/                 project documentation
.github/workflows/    CI/CD and mobile builds
```

## Security and privacy

This repository is public. Do not commit real IC numbers, passwords, session tokens, Cloudflare credentials, private staff photos, attendance selfies, sensitive incident data or private GPS trails.

## Product direction

ZPatrol is evolving as a **multi-site guard operations platform** built around one operating principle:

> Guards should be able to perform core patrol duties even when connectivity is unreliable, while authorized administrators retain a centralized and auditable operational record when the cloud is available.
