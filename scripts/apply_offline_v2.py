#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"Missing marker: {label}")
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, repl: str, label: str, flags: int = 0) -> str:
    out, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"Expected one replacement for {label}, got {count}")
    return out


# ---------------------------------------------------------------------------
# Offline models: enrich bootstrap so attendance can work even before the user
# has opened the attendance screen online once.
# ---------------------------------------------------------------------------
path = "lib/core/offline/offline_models.dart"
t = read(path)
bootstrap = r'''class OfflineBootstrap {
  const OfflineBootstrap({
    required this.generatedAt,
    required this.user,
    required this.departmentId,
    required this.departmentName,
    required this.sessionIntervalMinutes,
    this.sessionStartMinutes = 420,
    required this.routeOrderEnforced,
    required this.checkpoints,
    this.attendanceLatitude,
    this.attendanceLongitude,
    this.attendanceRadiusMeters = 150,
    this.attendanceLocationLabel = '',
    this.attendanceNextPunchType = 'IN',
    this.attendanceRecords = const [],
    this.profilePictureConfigured = false,
  });

  final DateTime generatedAt;
  final AppUser user;
  final int departmentId;
  final String departmentName;
  final int sessionIntervalMinutes;
  final int sessionStartMinutes;
  final bool routeOrderEnforced;
  final List<CachedCheckpoint> checkpoints;
  final double? attendanceLatitude;
  final double? attendanceLongitude;
  final int attendanceRadiusMeters;
  final String attendanceLocationLabel;
  final String attendanceNextPunchType;
  final List<Map<String, dynamic>> attendanceRecords;
  final bool profilePictureConfigured;

  Map<String, dynamic> toJson() => {
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'user': {
      'id': user.id,
      'nama': user.nama,
      'noKadPengenalan': user.noKadPengenalan,
      'jawatan': user.jawatan,
      'jabatan': user.jabatan,
      'profilePicture': user.profilePicture,
      'departmentId': user.departmentId,
      'sessionIntervalMinutes': user.sessionIntervalMinutes,
      'sessionStartMinutes': user.sessionStartMinutes,
      'noPk': user.noPk,
      'guardStatus': user.guardStatus,
      'active': user.active,
    },
    'department': {
      'id': departmentId,
      'name': departmentName,
      'sessionIntervalMinutes': sessionIntervalMinutes,
      'sessionStartMinutes': sessionStartMinutes,
      'routeOrderEnforced': routeOrderEnforced,
      'attendanceLatitude': attendanceLatitude,
      'attendanceLongitude': attendanceLongitude,
      'attendanceRadiusMeters': attendanceRadiusMeters,
      'attendanceLocationLabel': attendanceLocationLabel,
    },
    'checkpoints': checkpoints.map((item) => item.toJson()).toList(),
    'attendance': {
      'nextPunchType': attendanceNextPunchType,
      'records': attendanceRecords,
      'profilePictureConfigured': profilePictureConfigured,
    },
  };

  factory OfflineBootstrap.fromJson(Map<String, dynamic> json) {
    final department = Map<String, dynamic>.from(json['department'] as Map);
    final attendance = Map<String, dynamic>.from(
      json['attendance'] as Map? ?? const {},
    );
    final rows = json['checkpoints'] as List<dynamic>? ?? const [];
    final attendanceRows = attendance['records'] as List<dynamic>? ?? const [];
    return OfflineBootstrap(
      generatedAt:
          DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      user: AppUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      departmentId: (department['id'] as num).toInt(),
      departmentName: department['name'] as String,
      sessionIntervalMinutes:
          (department['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,
      sessionStartMinutes:
          (department['sessionStartMinutes'] as num?)?.toInt() ?? 420,
      routeOrderEnforced: department['routeOrderEnforced'] as bool? ?? true,
      checkpoints: rows
          .map(
            (item) => CachedCheckpoint.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      attendanceLatitude: (department['attendanceLatitude'] as num?)?.toDouble(),
      attendanceLongitude: (department['attendanceLongitude'] as num?)?.toDouble(),
      attendanceRadiusMeters:
          (department['attendanceRadiusMeters'] as num?)?.toInt() ?? 150,
      attendanceLocationLabel:
          department['attendanceLocationLabel'] as String? ?? '',
      attendanceNextPunchType:
          attendance['nextPunchType'] as String? ?? 'IN',
      attendanceRecords: attendanceRows
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      profilePictureConfigured:
          attendance['profilePictureConfigured'] as bool? ?? false,
    );
  }
}'''
t = regex_once(
    t,
    r"class OfflineBootstrap \{.*?\n\}\n\nclass OfflineEvent",
    bootstrap + "\n\nclass OfflineEvent",
    "OfflineBootstrap",
    re.S,
)
write(path, t)


# ---------------------------------------------------------------------------
# Offline store: bounded GET cache + aggressive cleanup for media-heavy synced
# events so the app remains small even after months of use.
# ---------------------------------------------------------------------------
path = "lib/core/offline/offline_store.dart"
t = read(path)
t = once(
    t,
    "  static const _activePatrolKeyPrefix = 'active_patrol_';\n",
    "  static const _activePatrolKeyPrefix = 'active_patrol_';\n"
    "  static const _httpCachePrefix = 'http_cache_v1:';\n"
    "  static const _httpCacheMaxEntries = 250;\n"
    "  static const _httpCacheMaxCharacters = 20 * 1024 * 1024;\n",
    "offline cache constants",
)
t = once(
    t,
    "    await purgeSyncedOlderThan(const Duration(days: 45));\n",
    "    await purgeSyncedOlderThan(const Duration(days: 14));\n"
    "    await purgeHttpCacheOlderThan(const Duration(days: 90));\n"
    "    await trimHttpCache();\n",
    "offline init cleanup",
)

http_methods = r'''
  Future<void> cacheHttpResponse(
    String key,
    String body, {
    int statusCode = 200,
  }) async {
    if (!_ready) return;
    if (body.length > 2 * 1024 * 1024) return;
    final scopedKey = _scopedHttpKey(key);
    await _cacheBox.put(scopedKey, {
      'body': body,
      'statusCode': statusCode,
      'storedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await trimHttpCache();
  }

  Map<String, dynamic>? cachedHttpResponse(String key) {
    if (!_ready) return null;
    final value = _cacheBox.get(_scopedHttpKey(key));
    if (value is! Map) return null;
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> purgeHttpCacheOlderThan(Duration age) async {
    if (!_ready) return;
    final cutoff = DateTime.now().toUtc().subtract(age);
    final keys = <dynamic>[];
    for (final key in _cacheBox.keys) {
      if (key is! String || !key.startsWith(_httpCachePrefix)) continue;
      final value = _cacheBox.get(key);
      if (value is! Map) {
        keys.add(key);
        continue;
      }
      final storedAt = DateTime.tryParse(value['storedAt'] as String? ?? '');
      if (storedAt == null || storedAt.isBefore(cutoff)) keys.add(key);
    }
    if (keys.isNotEmpty) await _cacheBox.deleteAll(keys);
  }

  Future<void> trimHttpCache() async {
    if (!_ready) return;
    final entries = <MapEntry<dynamic, Map<String, dynamic>>>[];
    for (final key in _cacheBox.keys) {
      if (key is! String || !key.startsWith(_httpCachePrefix)) continue;
      final value = _cacheBox.get(key);
      if (value is! Map) continue;
      entries.add(MapEntry(key, Map<String, dynamic>.from(value)));
    }
    entries.sort((a, b) {
      final aDate = DateTime.tryParse(a.value['storedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final bDate = DateTime.tryParse(b.value['storedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return aDate.compareTo(bDate);
    });
    var characters = entries.fold<int>(
      0,
      (sum, item) => sum + (item.value['body'] as String? ?? '').length,
    );
    final keysToDelete = <dynamic>[];
    while (entries.length - keysToDelete.length > _httpCacheMaxEntries ||
        characters > _httpCacheMaxCharacters) {
      final index = keysToDelete.length;
      if (index >= entries.length) break;
      final item = entries[index];
      keysToDelete.add(item.key);
      characters -= (item.value['body'] as String? ?? '').length;
    }
    if (keysToDelete.isNotEmpty) await _cacheBox.deleteAll(keysToDelete);
  }

  String _scopedHttpKey(String key) {
    final userId = cachedUser()?.id ?? 0;
    return '$_httpCachePrefix$userId::$key';
  }
'''
t = once(
    t,
    "  String get nfcMode {\n",
    http_methods + "\n  String get nfcMode {\n",
    "HTTP cache methods",
)

# Remove image-heavy payloads immediately after a successful sync.
t = regex_once(
    t,
    r"  Future<void> markSynced\(String id\) async \{.*?\n  \}\n\n  Future<void> markFailed",
    r'''  Future<void> markSynced(String id) async {
    final event = _event(id);
    if (event == null) return;
    if (event.type == 'attendance' || event.type == 'incident') {
      await _eventsBox.delete(id);
      notifyListeners();
      return;
    }
    await _eventsBox.put(
      id,
      event
          .copyWith(
            status: 'synced',
            attempts: event.attempts + 1,
            clearError: true,
            syncedAt: DateTime.now(),
          )
          .toJson(),
    );
    notifyListeners();
  }

  Future<void> markFailed''',
    "markSynced media cleanup",
    re.S,
)

t = once(
    t,
    "    'sessionIntervalMinutes': user.sessionIntervalMinutes,\n    'active': user.active,\n",
    "    'sessionIntervalMinutes': user.sessionIntervalMinutes,\n"
    "    'sessionStartMinutes': user.sessionStartMinutes,\n"
    "    'noPk': user.noPk,\n"
    "    'guardStatus': user.guardStatus,\n"
    "    'active': user.active,\n",
    "cached user metadata",
)
write(path, t)


# ---------------------------------------------------------------------------
# API service: all normal GETs become cache-first-on-failure. Attendance gets a
# true offline queue and returns an optimistic local record.
# ---------------------------------------------------------------------------
path = "lib/core/api/api_service.dart"
t = read(path)
t = once(t, "import 'dart:convert';\n", "import 'dart:convert';\nimport 'dart:math' as math;\n", "math import")
# Convert every API GET to the bounded offline cache helper. The helper itself is
# inserted afterwards and therefore keeps its own raw http.get call.
t = t.replace("await http.get(", "await _cachedGet(")

cached_get = r'''
  Future<http.Response> _cachedGet(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final cacheKey = uri.toString();
    try {
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.bodyBytes.length <= 2 * 1024 * 1024) {
        await _offline.cacheHttpResponse(
          cacheKey,
          response.body,
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode >= 500) {
        final cached = _offline.cachedHttpResponse(cacheKey);
        if (cached != null) return _cachedResponse(cached);
      }
      return response;
    } catch (_) {
      final cached = _offline.cachedHttpResponse(cacheKey);
      if (cached != null) return _cachedResponse(cached);
      rethrow;
    }
  }

  http.Response _cachedResponse(Map<String, dynamic> cached) => http.Response(
    cached['body'] as String? ?? '{}',
    (cached['statusCode'] as num?)?.toInt() ?? 200,
    headers: const {'x-zpatrol-source': 'offline-cache'},
  );
'''
t = once(
    t,
    "  Future<AppUser> login(String identityCard) async {\n",
    cached_get + "\n  Future<AppUser> login(String identityCard) async {\n",
    "cached GET helper",
)

old_attendance = r'''  Future<AttendanceStatus> getAttendanceStatus() async =>
      AttendanceStatus.fromJson(
        _decode(
          await _cachedGet(_uri('/api/attendance/status'), headers: _headers()),
        ),
      );

  Future<AttendanceRecord> punchAttendance({
    required double latitude,
    required double longitude,
    required double accuracy,
    required String selfieData,
  }) async {
    final data = _decode(
      await http.post(
        _uri('/api/attendance/punch'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'selfie': selfieData,
        }),
      ),
    );
    return AttendanceRecord.fromJson(
      Map<String, dynamic>.from(data['record'] as Map),
    );
  }
'''
new_attendance = r'''  Future<AttendanceStatus> getAttendanceStatus() async {
    try {
      return AttendanceStatus.fromJson(
        _decode(
          await _cachedGet(_uri('/api/attendance/status'), headers: _headers()),
        ),
      );
    } catch (_) {
      final bootstrap = _offline.cachedBootstrap();
      if (bootstrap == null) rethrow;
      return AttendanceStatus(
        department: DepartmentRecord(
          id: bootstrap.departmentId,
          name: bootstrap.departmentName,
          sessionIntervalMinutes: bootstrap.sessionIntervalMinutes,
          sessionStartMinutes: bootstrap.sessionStartMinutes,
          active: true,
          checkpointCount: bootstrap.checkpoints.length,
          attendanceLatitude: bootstrap.attendanceLatitude,
          attendanceLongitude: bootstrap.attendanceLongitude,
          attendanceRadiusMeters: bootstrap.attendanceRadiusMeters,
          attendanceLocationLabel: bootstrap.attendanceLocationLabel,
        ),
        nextPunchType: bootstrap.attendanceNextPunchType,
        records: bootstrap.attendanceRecords
            .map((item) => AttendanceRecord.fromJson(item))
            .toList(),
        profilePictureConfigured: bootstrap.profilePictureConfigured,
      );
    }
  }

  Future<AttendanceRecord> punchAttendance({
    required double latitude,
    required double longitude,
    required double accuracy,
    required String selfieData,
  }) async {
    final occurredAt = DateTime.now();
    final payload = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'selfie': selfieData,
    };

    if (accuracy < 0 || accuracy > 100) {
      throw const ApiException(
        'Ketepatan GPS belum mencukupi. Cuba bergerak ke kawasan terbuka.',
        statusCode: 422,
      );
    }
    if (selfieData.length > 650000) {
      throw const ApiException('Selfie terlalu besar. Ambil gambar semula.', statusCode: 413);
    }

    final bootstrap = _offline.cachedBootstrap();
    if (bootstrap?.attendanceLatitude != null &&
        bootstrap?.attendanceLongitude != null) {
      final distance = _haversineMeters(
        latitude,
        longitude,
        bootstrap!.attendanceLatitude!,
        bootstrap.attendanceLongitude!,
      );
      if (distance > bootstrap.attendanceRadiusMeters) {
        throw ApiException(
          'Anda berada ${distance.round()}m dari pusat kawasan. Had Sekolah ialah ${bootstrap.attendanceRadiusMeters}m.',
          statusCode: 403,
        );
      }
    }

    try {
      final response = await http
          .post(
            _uri('/api/attendance/punch'),
            headers: _headers(jsonBody: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode >= 500) {
        throw ApiException(
          'Pelayan tidak dapat dicapai.',
          statusCode: response.statusCode,
        );
      }
      final data = _decode(response);
      return AttendanceRecord.fromJson(
        Map<String, dynamic>.from(data['record'] as Map),
      );
    } catch (error) {
      if (error is ApiException &&
          error.statusCode != null &&
          error.statusCode! < 500) {
        rethrow;
      }
      final user = _offline.cachedUser();
      if (user == null) rethrow;

      var punchType = 'IN';
      try {
        punchType = (await getAttendanceStatus()).nextPunchType;
      } catch (_) {
        punchType = bootstrap?.attendanceNextPunchType ?? 'IN';
      }

      await _offline.queueEvent(
        userId: user.id,
        type: 'attendance',
        occurredAt: occurredAt,
        location: {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
        },
        payload: payload,
      );

      return AttendanceRecord(
        id: -occurredAt.microsecondsSinceEpoch,
        punchType: punchType,
        punchedAt: occurredAt,
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracy,
        distanceMeters: 0,
        faceStatus: 'pending_sync',
        faceReason: 'Punch disimpan pada peranti dan akan disegerakkan automatik.',
        userId: user.id,
        userName: user.nama,
        departmentId: user.departmentId,
        department: user.jabatan,
      );
    }
  }
'''
t = once(t, old_attendance, new_attendance, "attendance local-first methods")

haversine = r'''
  double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    double radians(double value) => value * math.pi / 180.0;
    final dLat = radians(lat2 - lat1);
    final dLon = radians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(radians(lat1)) *
            math.cos(radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
'''
t = once(
    t,
    "  String _dateKey(DateTime value) {\n",
    haversine + "\n  String _dateKey(DateTime value) {\n",
    "haversine helper",
)
write(path, t)


# ---------------------------------------------------------------------------
# Attendance UI: optimistic local record and explicit pending-sync state.
# ---------------------------------------------------------------------------
path = "lib/features/attendance/attendance_screen.dart"
t = read(path)
old = r'''      await widget.api.punchAttendance(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        selfieData: dataUrl,
      );
      await _refresh();
      if (!mounted) return;
'''
new = r'''      final record = await widget.api.punchAttendance(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        selfieData: dataUrl,
      );
      if (!mounted) return;
      if (record.id < 0) {
        final current = _status;
        if (current != null) {
          setState(() {
            _status = AttendanceStatus(
              department: current.department,
              nextPunchType: record.punchType == 'IN' ? 'OUT' : 'IN',
              records: [...current.records, record],
              profilePictureConfigured: current.profilePictureConfigured,
            );
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Offline: punch disimpan pada telefon dan akan sync automatik.',
            ),
          ),
        );
      } else {
        await _refresh();
      }
'''
t = once(t, old, new, "attendance optimistic punch")
t = once(
    t,
    "    'matched' => 'WAJAH SEPADAN',\n    'different' => 'WAJAH TIDAK SEPADAN',\n",
    "    'matched' => 'WAJAH SEPADAN',\n"
    "    'different' => 'WAJAH TIDAK SEPADAN',\n"
    "    'pending_sync' => 'MENUNGGU SYNC',\n",
    "attendance pending label",
)
t = once(
    t,
    "    'matched' => const Color(0xFF00B894),\n    'different' => const Color(0xFFFF7675),\n",
    "    'matched' => const Color(0xFF00B894),\n"
    "    'different' => const Color(0xFFFF7675),\n"
    "    'pending_sync' => const Color(0xFFFDCB6E),\n",
    "attendance pending color",
)
t = once(
    t,
    "                          subtitle: Text(\n                            '${record.distanceMeters.toStringAsFixed(0)}m dari pusat • GPS ±${record.accuracyMeters?.toStringAsFixed(0) ?? '-'}m',\n                          ),\n",
    "                          subtitle: Text(\n"
    "                            record.id < 0\n"
    "                                ? 'Disimpan offline • GPS ±${record.accuracyMeters?.toStringAsFixed(0) ?? '-'}m • akan sync automatik'\n"
    "                                : '${record.distanceMeters.toStringAsFixed(0)}m dari pusat • GPS ±${record.accuracyMeters?.toStringAsFixed(0) ?? '-'}m',\n"
    "                          ),\n",
    "attendance pending subtitle",
)
write(path, t)


# ---------------------------------------------------------------------------
# Cloudflare offline worker: bootstrap carries attendance data and the sync
# endpoint accepts attendance events idempotently.
# ---------------------------------------------------------------------------
path = "worker/offline.js"
t = read(path)
t = once(
    t,
    "const MAX_EVENT_AGE_MS = 180 * 24 * 60 * 60 * 1000;\n",
    "const MAX_EVENT_AGE_MS = 180 * 24 * 60 * 60 * 1000;\n"
    "const MAX_SELFIE_CHARS = 650000;\n"
    "const DEFAULT_ATTENDANCE_RADIUS_M = 150;\n",
    "offline worker attendance constants",
)
t = once(
    t,
    "    `SELECT id, name, session_interval_minutes, session_start_minutes, route_order_enforced\n"
    "     FROM departments WHERE id = ? AND active = 1 LIMIT 1`,\n",
    "    `SELECT id, name, session_interval_minutes, session_start_minutes, route_order_enforced,\n"
    "            attendance_latitude, attendance_longitude, attendance_radius_m,\n"
    "            attendance_location_label\n"
    "     FROM departments WHERE id = ? AND active = 1 LIMIT 1`,\n",
    "bootstrap department attendance fields",
)

attendance_bootstrap_query = r'''
  const workDate = malaysiaDateKey(new Date());
  const attendanceResult = await env.DB.prepare(
    `SELECT id, punch_type, punched_at, latitude, longitude, accuracy_m, distance_m,
            face_status, face_score, face_model, face_reason
     FROM attendance_records
     WHERE user_id = ? AND work_date = ?
     ORDER BY punched_at ASC, id ASC`,
  ).bind(auth.user.id, workDate).all();
  const attendanceRecords = (attendanceResult.results ?? []).map((row) => ({
    id: Number(row.id),
    punchType: row.punch_type,
    punchedAt: row.punched_at,
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    accuracyMeters: row.accuracy_m == null ? null : Number(row.accuracy_m),
    distanceMeters: Number(row.distance_m || 0),
    faceStatus: row.face_status || 'review_required',
    faceScore: row.face_score == null ? null : Number(row.face_score),
    faceModel: row.face_model || null,
    faceReason: row.face_reason || null,
  }));
  const latestAttendance = attendanceRecords.length
    ? attendanceRecords[attendanceRecords.length - 1]
    : null;
'''
t = once(
    t,
    "  const checkpointsResult = await env.DB.prepare(\n"
    "    `SELECT id, name, nfc_uid, position, job_instruction\n"
    "     FROM checkpoints\n"
    "     WHERE department_id = ? AND active = 1\n"
    "     ORDER BY position ASC, id ASC`,\n"
    "  ).bind(auth.user.department_id).all();\n\n",
    "  const checkpointsResult = await env.DB.prepare(\n"
    "    `SELECT id, name, nfc_uid, position, job_instruction\n"
    "     FROM checkpoints\n"
    "     WHERE department_id = ? AND active = 1\n"
    "     ORDER BY position ASC, id ASC`,\n"
    "  ).bind(auth.user.department_id).all();\n"
    + attendance_bootstrap_query + "\n",
    "attendance bootstrap query",
)

t = once(
    t,
    "      routeOrderEnforced: false,\n    },\n",
    "      routeOrderEnforced: false,\n"
    "      attendanceLatitude: department.attendance_latitude == null ? null : Number(department.attendance_latitude),\n"
    "      attendanceLongitude: department.attendance_longitude == null ? null : Number(department.attendance_longitude),\n"
    "      attendanceRadiusMeters: Math.max(30, Number(department.attendance_radius_m || DEFAULT_ATTENDANCE_RADIUS_M)),\n"
    "      attendanceLocationLabel: department.attendance_location_label || '',\n"
    "    },\n",
    "attendance bootstrap department response",
)
t = once(
    t,
    "    checkpoints: (checkpointsResult.results ?? []).map((row) => ({\n"
    "      id: Number(row.id),\n"
    "      name: row.name,\n"
    "      nfcUid: row.nfc_uid,\n"
    "      position: Number(row.position),\n"
    "      instruction: row.job_instruction || null,\n"
    "    })),\n"
    "    syncPolicy: {\n",
    "    checkpoints: (checkpointsResult.results ?? []).map((row) => ({\n"
    "      id: Number(row.id),\n"
    "      name: row.name,\n"
    "      nfcUid: row.nfc_uid,\n"
    "      position: Number(row.position),\n"
    "      instruction: row.job_instruction || null,\n"
    "    })),\n"
    "    attendance: {\n"
    "      nextPunchType: latestAttendance?.punchType === 'IN' ? 'OUT' : 'IN',\n"
    "      records: attendanceRecords,\n"
    "      profilePictureConfigured: Boolean(auth.user.profile_picture),\n"
    "    },\n"
    "    syncPolicy: {\n",
    "attendance bootstrap response",
)

t = once(
    t,
    "        case 'incident':\n          result = await syncIncident(env, auth.user, clientEventId, occurredAt, payload);\n          break;\n",
    "        case 'incident':\n"
    "          result = await syncIncident(env, auth.user, clientEventId, occurredAt, payload);\n"
    "          break;\n"
    "        case 'attendance':\n"
    "          result = await syncAttendance(env, auth.user, clientEventId, occurredAt, payload);\n"
    "          break;\n",
    "attendance event switch",
)

sync_attendance = r'''
async function syncAttendance(env, user, clientEventId, occurredAt, payload) {
  if (!user.department_id) throw new SyncError('Sekolah pengguna tidak ditetapkan.');
  if (!user.profile_picture) {
    throw new SyncError('Gambar profil diperlukan sebelum punch kehadiran offline.');
  }

  const latitude = Number(payload.latitude);
  const longitude = Number(payload.longitude);
  const accuracy = Number(payload.accuracy ?? 9999);
  const selfie = String(payload.selfie ?? '');
  if (!validCoordinate(latitude, longitude)) throw new SyncError('Lokasi semasa tidak sah.');
  if (!Number.isFinite(accuracy) || accuracy < 0 || accuracy > 100) {
    throw new SyncError('Ketepatan GPS punch offline tidak mencukupi.');
  }
  if (!/^data:image\/(jpeg|jpg|png|webp);base64,/i.test(selfie)) {
    throw new SyncError('Selfie kehadiran offline tidak sah.');
  }
  if (selfie.length > MAX_SELFIE_CHARS) throw new SyncError('Selfie kehadiran terlalu besar.');

  const department = await env.DB.prepare(
    `SELECT id, name, attendance_latitude, attendance_longitude, attendance_radius_m
     FROM departments WHERE id = ? AND active = 1 LIMIT 1`,
  ).bind(user.department_id).first();
  if (!department) throw new SyncError('Sekolah tidak ditemui.');

  const centerLat = Number(department.attendance_latitude);
  const centerLng = Number(department.attendance_longitude);
  const radius = Math.max(30, Number(department.attendance_radius_m || DEFAULT_ATTENDANCE_RADIUS_M));
  if (!Number.isFinite(centerLat) || !Number.isFinite(centerLng)) {
    throw new SyncError('Kawasan kehadiran Sekolah belum ditetapkan.');
  }
  const distance = haversineMeters(latitude, longitude, centerLat, centerLng);
  if (distance > radius) {
    throw new SyncError(`Punch offline berada ${Math.round(distance)}m dari pusat; had ialah ${Math.round(radius)}m.`);
  }

  const workDate = malaysiaDateKey(occurredAt);
  const latest = await env.DB.prepare(
    `SELECT id, punch_type, punched_at
     FROM attendance_records
     WHERE user_id = ? AND work_date = ? AND punched_at <= ?
     ORDER BY punched_at DESC, id DESC LIMIT 1`,
  ).bind(user.id, workDate, occurredAt.toISOString()).first();
  if (latest && occurredAt.getTime() - Date.parse(latest.punched_at) < 60000) {
    throw new SyncError('Punch offline terlalu rapat dengan rekod sebelumnya.');
  }
  const punchType = latest?.punch_type === 'IN' ? 'OUT' : 'IN';
  const profileHash = await sha256(user.profile_picture);
  const faceStatus = 'review_required';
  const faceModel = 'offline-sync';
  const faceReason = 'Punch dibuat tanpa internet; selfie disimpan untuk semakan selepas sync.';

  const insert = await env.DB.prepare(
    `INSERT INTO attendance_records (
       user_id, department_id, work_date, punch_type, punched_at,
       latitude, longitude, accuracy_m, distance_m, selfie_data,
       profile_picture_hash, face_status, face_score, face_model, face_reason
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    user.id,
    user.department_id,
    workDate,
    punchType,
    occurredAt.toISOString(),
    latitude,
    longitude,
    accuracy,
    distance,
    selfie,
    profileHash,
    faceStatus,
    null,
    faceModel,
    faceReason,
  ).run();

  const attendanceId = Number(insert.meta?.last_row_id || 0);
  try {
    await sendPushToUser(env, user.id, {
      title: 'Kehadiran Offline Disinkron',
      body: `${department.name} • ${punchType} berjaya dihantar ke pelayan.`,
      kind: 'attendance_punch',
      data: { attendanceId, workDate, punchType, offline: true },
    });
  } catch (error) {
    console.error('Offline attendance confirmation push failed', error);
  }

  return {
    serverId: attendanceId,
    clientEventId,
    punchType,
    punchedAt: occurredAt.toISOString(),
    distanceMeters: distance,
  };
}
'''
t = once(
    t,
    "async function syncIncident(env, user, clientEventId, occurredAt, payload) {\n",
    sync_attendance + "\nasync function syncIncident(env, user, clientEventId, occurredAt, payload) {\n",
    "syncAttendance function",
)

geo_helpers = r'''
function validCoordinate(lat, lng) {
  return Number.isFinite(lat) && Number.isFinite(lng) &&
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const toRad = (value) => value * Math.PI / 180;
  const earthRadius = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
'''
t = once(
    t,
    "async function sha256(value) {\n",
    geo_helpers + "\nasync function sha256(value) {\n",
    "offline worker geofence helpers",
)
write(path, t)


# ---------------------------------------------------------------------------
# Version + release notes.
# ---------------------------------------------------------------------------
path = "pubspec.yaml"
t = read(path)
t = regex_once(t, r"version: [^\n]+", "version: 0.7.0+39", "version bump")
write(path, t)

release = ROOT / "release/offline-engine-v2-0.7.0+39-20260911.txt"
release.parent.mkdir(parents=True, exist_ok=True)
release.write_text(
    """ZPatrol Offline Engine v2 — 0.7.0+39\n"
    "Date: 2026-09-11\n"
    "- Bounded local cache for normal API GET data (90-day max age, ~20 MB cap).\n"
    "- Offline fallback for history, users, checkpoints, reports, attendance, command center and other GET-backed screens.\n"
    "- Attendance punch now queues offline with GPS + selfie and syncs idempotently.\n"
    "- Offline attendance uses cached/bootstrapped school geofence data.\n"
    "- Synced media-heavy events are removed immediately; other synced events retained 14 days.\n"
    "- Existing patrol, checkpoint, SOS and incident offline queue preserved.\n"
    "- Admin configuration writes remain online-only to avoid destructive conflict resolution.\n"
    """,
    encoding="utf-8",
)

print("Offline Engine v2 migration applied.")
