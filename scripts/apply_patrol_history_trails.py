from pathlib import Path
import re

ROOT = Path('.')


def replace_once(text, pattern, replacement, label, flags=0):
    updated, count = re.subn(pattern, lambda _match: replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 replacement, got {count}')
    return updated

# 1) Durable patrol session archive migration.
migration = ROOT / 'migrations/0011_patrol_session_history.sql'
migration.write_text("""CREATE TABLE IF NOT EXISTS patrol_session_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  department_id INTEGER,
  client_session_id TEXT NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, client_session_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_patrol_session_history_department_time
  ON patrol_session_history(department_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_patrol_session_history_user_time
  ON patrol_session_history(user_id, started_at DESC);

INSERT OR IGNORE INTO patrol_session_history
  (user_id, department_id, client_session_id, started_at, ended_at, updated_at)
SELECT
  user_id,
  MAX(department_id),
  client_session_id,
  MIN(CASE WHEN event_type = 'start' THEN occurred_at END),
  MAX(CASE WHEN event_type = 'end' THEN occurred_at END),
  CURRENT_TIMESTAMP
FROM patrol_activity_log
GROUP BY user_id, client_session_id
HAVING MIN(CASE WHEN event_type = 'start' THEN occurred_at END) IS NOT NULL;

INSERT OR IGNORE INTO patrol_session_history
  (user_id, department_id, client_session_id, started_at, ended_at, updated_at)
SELECT user_id, department_id, client_session_id, started_at, ended_at, updated_at
FROM live_patrol_presence
WHERE started_at IS NOT NULL;
""", encoding='utf-8')

# 2) Worker history endpoint: department selection + archived patrol runs/trails.
index_path = ROOT / 'worker/index.js'
index = index_path.read_text(encoding='utf-8')
new_get_scans = r'''async function getScans(request, env, url) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;

  const requestedDate = url.searchParams.get('date') || malaysiaDateKey(new Date());
  if (!/^\d{4}-\d{2}-\d{2}$/.test(requestedDate)) {
    return json({ error: 'Tarikh tidak sah.' }, 400);
  }

  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const requestedDepartment = url.searchParams.get('departmentId');
  let departmentId = Number(auth.user.department_id || 0);
  if (requestedDepartment != null && requestedDepartment !== '') {
    const parsed = Number(requestedDepartment);
    if (!Number.isInteger(parsed) || parsed <= 0) {
      return json({ error: 'Jabatan tidak sah.' }, 400);
    }
    if (role !== 'management' && parsed !== departmentId) {
      return json({ error: 'Anda hanya boleh melihat Sejarah Rondaan Jabatan sendiri.' }, 403);
    }
    departmentId = parsed;
  }
  if (!departmentId) {
    return json({ error: 'Pengguna belum dipautkan kepada Jabatan.' }, 409);
  }

  const department = await env.DB.prepare(
    `SELECT id, name, session_interval_minutes, session_start_minutes
     FROM departments WHERE id = ? LIMIT 1`,
  ).bind(departmentId).first();
  if (!department) return json({ error: 'Jabatan tidak ditemui.' }, 404);

  const calendarBounds = malaysiaDayBounds(requestedDate);
  if (!calendarBounds) return json({ error: 'Tarikh tidak sah.' }, 400);

  const sessionStartMinutes = Math.max(
    0,
    Math.min(1439, Number(department.session_start_minutes ?? 420)),
  );
  const interval = Math.max(
    15,
    Math.min(1440, Number(department.session_interval_minutes || 120)),
  );
  const firstWindow = sessionWindow(
    new Date(calendarBounds.startMs),
    interval,
    sessionStartMinutes,
  );
  const lastWindow = sessionWindow(
    new Date(calendarBounds.endMs - 1),
    interval,
    sessionStartMinutes,
  );
  const queryStartIso = new Date(firstWindow.startMs).toISOString();
  const queryEndIso = new Date(lastWindow.endMs).toISOString();
  const calendarStartIso = new Date(calendarBounds.startMs).toISOString();
  const calendarEndIso = new Date(calendarBounds.endMs).toISOString();

  const [checkpointResult, scanResult, patrolResult, trailResult] = await Promise.all([
    env.DB.prepare(
      `SELECT id, name, position
       FROM checkpoints
       WHERE department_id = ? AND active = 1
       ORDER BY position ASC, id ASC`,
    ).bind(departmentId).all(),
    env.DB.prepare(
      `SELECT s.id, s.user_id, s.nfc_uid, s.scanned_at, s.checkpoint_id,
              s.session_index, c.name AS checkpoint_name,
              u.nama AS user_name, u.profile_picture
       FROM nfc_scans s
       JOIN users u ON u.id = s.user_id
       LEFT JOIN checkpoints c ON c.id = s.checkpoint_id
       WHERE COALESCE(c.department_id, u.department_id) = ?
         AND s.scanned_at >= ? AND s.scanned_at < ?
       ORDER BY s.scanned_at ASC, s.id ASC`,
    ).bind(departmentId, queryStartIso, queryEndIso).all(),
    env.DB.prepare(
      `SELECT h.user_id, h.client_session_id, h.started_at, h.ended_at,
              u.nama AS user_name, u.profile_picture
       FROM patrol_session_history h
       JOIN users u ON u.id = h.user_id
       WHERE h.department_id = ?
         AND h.started_at >= ? AND h.started_at < ?
       ORDER BY h.started_at DESC, h.id DESC`,
    ).bind(departmentId, calendarStartIso, calendarEndIso).all(),
    env.DB.prepare(
      `SELECT t.user_id, t.client_session_id, t.latitude, t.longitude,
              t.accuracy, t.recorded_at
       FROM live_patrol_trail t
       JOIN patrol_session_history h
         ON h.user_id = t.user_id
        AND h.client_session_id = t.client_session_id
       WHERE h.department_id = ?
         AND h.started_at >= ? AND h.started_at < ?
       ORDER BY t.user_id ASC, t.client_session_id ASC, t.recorded_at ASC`,
    ).bind(departmentId, calendarStartIso, calendarEndIso).all(),
  ]);

  const checkpoints = checkpointResult.results ?? [];
  const scans = scanResult.results ?? [];
  const trails = new Map();
  for (const row of trailResult.results ?? []) {
    const key = `${Number(row.user_id)}:${row.client_session_id}`;
    const list = trails.get(key) ?? [];
    list.push({
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      accuracy: row.accuracy == null ? null : Number(row.accuracy),
      recordedAt: row.recorded_at,
    });
    trails.set(key, list);
  }

  const patrolRuns = (patrolResult.results ?? []).map((row) => {
    const key = `${Number(row.user_id)}:${row.client_session_id}`;
    const allTrail = trails.get(key) ?? [];
    const trail = compactTrail(allTrail, 500);
    const startMs = Date.parse(row.started_at);
    const endedAt = row.ended_at || null;
    const endMs = endedAt ? Date.parse(endedAt) : null;
    const runWindow = sessionWindow(new Date(startMs), interval, sessionStartMinutes);
    return {
      userId: Number(row.user_id),
      userName: row.user_name,
      profilePicture: row.profile_picture || null,
      clientSessionId: row.client_session_id,
      sessionIndex: runWindow.index,
      startedAt: row.started_at,
      endedAt,
      durationSeconds: endMs == null ? null : Math.max(0, Math.floor((endMs - startMs) / 1000)),
      trailPointCount: allTrail.length,
      trail,
    };
  });

  const nowMs = Date.now();
  const todayKey = malaysiaDateKey(new Date());
  const isPastDay = requestedDate < todayKey;
  const isFutureDay = requestedDate > todayKey;
  const sessions = [];

  if (!isFutureDay) {
    let cursor = firstWindow.startMs;
    while (cursor < calendarBounds.endMs) {
      const window = sessionWindow(
        new Date(cursor),
        interval,
        sessionStartMinutes,
      );
      const startMs = window.startMs;
      const endMs = window.endMs;
      if (startMs >= calendarBounds.endMs) break;
      if (requestedDate === todayKey && startMs > nowMs) break;

      const fullSessionScans = scans.filter((scan) => {
        const time = Date.parse(scan.scanned_at);
        return time >= startMs && time < endMs;
      });
      const calendarScans = fullSessionScans.filter((scan) => {
        const time = Date.parse(scan.scanned_at);
        return time >= calendarBounds.startMs && time < calendarBounds.endMs;
      });
      const scannedCheckpointIds = new Set(
        fullSessionScans
          .map((scan) => Number(scan.checkpoint_id || 0))
          .filter((id) => id > 0),
      );
      const missing = checkpoints.filter(
        (checkpoint) => !scannedCheckpointIds.has(Number(checkpoint.id)),
      );

      let status = 'in_progress';
      if (checkpoints.length === 0) status = 'no_checkpoints';
      else if (missing.length === 0) status = 'complete';
      else if (isPastDay || endMs <= nowMs) status = 'missed';

      const scannerIds = [...new Set(
        calendarScans
          .map((scan) => Number(scan.user_id || 0))
          .filter((id) => id > 0),
      )];
      const scannerNames = [...new Set(
        calendarScans
          .map((scan) => String(scan.user_name || '').trim())
          .filter(Boolean),
      )];
      const firstScan = calendarScans[0] ?? null;

      sessions.push({
        userId: scannerIds.length === 1 ? scannerIds[0] : 0,
        userName: scannerNames.length > 0
          ? scannerNames.join(', ')
          : 'Tiada pengawal direkodkan',
        profilePicture: scannerIds.length === 1
          ? (firstScan?.profile_picture || null)
          : null,
        index: window.index,
        startAt: new Date(startMs).toISOString(),
        endAt: new Date(endMs).toISOString(),
        status,
        expectedCount: checkpoints.length,
        scannedCount: scannedCheckpointIds.size,
        missingCheckpoints: missing.map((checkpoint) => ({
          id: checkpoint.id,
          name: checkpoint.name,
          position: checkpoint.position,
        })),
        scans: calendarScans.map(scanJson),
      });

      if (endMs <= cursor) break;
      cursor = endMs;
    }
    sessions.sort((left, right) => Date.parse(right.startAt) - Date.parse(left.startAt));
  }

  return json({
    date: requestedDate,
    departmentId: Number(department.id),
    department: department.name,
    sessionIntervalMinutes: interval,
    sessionStartMinutes,
    checkpoints,
    patrolRuns,
    sessions,
  });
}

function compactTrail(points, maxPoints = 500) {
  if (points.length <= maxPoints) return points;
  const step = Math.ceil(points.length / maxPoints);
  return points.filter((_, index) => index === 0 || index === points.length - 1 || index % step === 0);
}
'''
index = replace_once(
    index,
    r'async function getScans\(request, env, url\) \{.*?\n\}\n\nasync function createScan',
    new_get_scans + '\nasync function createScan',
    'worker/index.js getScans',
    flags=re.S,
)
index_path.write_text(index, encoding='utf-8')

# 3) Keep a durable session archive in sync with live and offline lifecycle events.
offline_path = ROOT / 'worker/offline.js'
offline = offline_path.read_text(encoding='utf-8')

live_start_marker = """  ).run();\n\n  return json({ ok: true, clientSessionId, startedAt: startedAt.toISOString() });\n}\n\nasync function liveLocation"""
live_start_replacement = """  ).run();\n\n  await env.DB.prepare(\n    `INSERT INTO patrol_session_history\n      (user_id, department_id, client_session_id, started_at, ended_at, updated_at)\n     VALUES (?, ?, ?, ?, NULL, ?)\n     ON CONFLICT(user_id, client_session_id) DO UPDATE SET\n       department_id = excluded.department_id,\n       started_at = CASE\n         WHEN excluded.started_at < patrol_session_history.started_at THEN excluded.started_at\n         ELSE patrol_session_history.started_at\n       END,\n       updated_at = excluded.updated_at`,\n  ).bind(\n    auth.user.id,\n    auth.user.department_id ?? null,\n    clientSessionId,\n    startedAt.toISOString(),\n    nowIso,\n  ).run();\n\n  return json({ ok: true, clientSessionId, startedAt: startedAt.toISOString() });\n}\n\nasync function liveLocation"""
if live_start_marker not in offline:
    raise SystemExit('worker/offline.js liveStart marker not found')
offline = offline.replace(live_start_marker, live_start_replacement, 1)

live_end_marker = """  await env.DB.prepare(\n    `UPDATE live_patrol_presence\n     SET active = 0, ended_at = ?, updated_at = ?\n     WHERE user_id = ? AND client_session_id = ?`,\n  ).bind(endedAt, endedAt, auth.user.id, clientSessionId).run();\n  return json({ ok: true, endedAt });\n}"""
live_end_replacement = """  await env.DB.prepare(\n    `UPDATE live_patrol_presence\n     SET active = 0, ended_at = ?, updated_at = ?\n     WHERE user_id = ? AND client_session_id = ?`,\n  ).bind(endedAt, endedAt, auth.user.id, clientSessionId).run();\n  await env.DB.prepare(\n    `UPDATE patrol_session_history\n     SET ended_at = ?, updated_at = ?\n     WHERE user_id = ? AND client_session_id = ?`,\n  ).bind(endedAt, endedAt, auth.user.id, clientSessionId).run();\n  return json({ ok: true, endedAt });\n}"""
if live_end_marker not in offline:
    raise SystemExit('worker/offline.js liveEnd marker not found')
offline = offline.replace(live_end_marker, live_end_replacement, 1)

sync_pattern = r'''(async function syncPatrolActivity\(env, user, clientEventId, occurredAt, type, payload\) \{.*?const insert = await env\.DB\.prepare\(\n    `INSERT INTO patrol_activity_log.*?\n  \)\.run\(\);)(\n  return \{ serverId: Number\(insert\.meta\?\.last_row_id \|\| 0\), clientEventId \};\n\})'''
sync_match = re.search(sync_pattern, offline, flags=re.S)
if not sync_match:
    raise SystemExit('worker/offline.js syncPatrolActivity block not found')
sync_extra = r'''
  const lifecycle = await env.DB.prepare(
    `SELECT
       MIN(CASE WHEN event_type = 'start' THEN occurred_at END) AS started_at,
       MAX(CASE WHEN event_type = 'end' THEN occurred_at END) AS ended_at
     FROM patrol_activity_log
     WHERE user_id = ? AND client_session_id = ?`,
  ).bind(user.id, clientSessionId).first();
  if (lifecycle?.started_at) {
    await env.DB.prepare(
      `INSERT INTO patrol_session_history
        (user_id, department_id, client_session_id, started_at, ended_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, client_session_id) DO UPDATE SET
         department_id = excluded.department_id,
         started_at = excluded.started_at,
         ended_at = COALESCE(excluded.ended_at, patrol_session_history.ended_at),
         updated_at = excluded.updated_at`,
    ).bind(
      user.id,
      user.department_id ?? null,
      clientSessionId,
      lifecycle.started_at,
      lifecycle.ended_at || null,
      new Date().toISOString(),
    ).run();
  }'''
offline = offline[:sync_match.start()] + sync_match.group(1) + sync_extra + sync_match.group(2) + offline[sync_match.end():]
offline_path.write_text(offline, encoding='utf-8')

# 4) API models + department-aware getHistory.
api_path = ROOT / 'lib/core/api/api_service.dart'
api = api_path.read_text(encoding='utf-8')
history_models = r'''class HistoryTrailPoint {
  const HistoryTrailPoint({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracy,
  });
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;

  factory HistoryTrailPoint.fromJson(Map<String, dynamic> json) =>
      HistoryTrailPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(json['recordedAt'] as String),
      );
}

class HistoryPatrolRun {
  const HistoryPatrolRun({
    required this.userId,
    required this.userName,
    required this.clientSessionId,
    required this.sessionIndex,
    required this.startedAt,
    required this.trailPointCount,
    required this.trail,
    this.profilePicture,
    this.endedAt,
    this.durationSeconds,
  });
  final int userId;
  final String userName;
  final String? profilePicture;
  final String clientSessionId;
  final int sessionIndex;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final int trailPointCount;
  final List<HistoryTrailPoint> trail;

  factory HistoryPatrolRun.fromJson(Map<String, dynamic> json) {
    final rows = json['trail'] as List<dynamic>? ?? const [];
    return HistoryPatrolRun(
      userId: (json['userId'] as num).toInt(),
      userName: json['userName'] as String? ?? 'Pengawal',
      profilePicture: json['profilePicture'] as String?,
      clientSessionId: json['clientSessionId'] as String,
      sessionIndex: (json['sessionIndex'] as num?)?.toInt() ?? 0,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] == null
          ? null
          : DateTime.parse(json['endedAt'] as String),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      trailPointCount: (json['trailPointCount'] as num?)?.toInt() ?? rows.length,
      trail: rows
          .map((item) => HistoryTrailPoint.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
    );
  }
}

class HistoryDay {
  const HistoryDay({
    required this.date,
    required this.departmentId,
    required this.department,
    required this.sessionIntervalMinutes,
    required this.patrolRuns,
    required this.sessions,
  });
  final String date;
  final int departmentId;
  final String department;
  final int sessionIntervalMinutes;
  final List<HistoryPatrolRun> patrolRuns;
  final List<HistorySession> sessions;

  factory HistoryDay.fromJson(Map<String, dynamic> json) {
    final patrolRuns = json['patrolRuns'] as List<dynamic>? ?? const [];
    final sessions = json['sessions'] as List<dynamic>? ?? const [];
    return HistoryDay(
      date: json['date'] as String,
      departmentId: (json['departmentId'] as num?)?.toInt() ?? 0,
      department: json['department'] as String? ?? '-',
      sessionIntervalMinutes:
          (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,
      patrolRuns: patrolRuns
          .map((item) => HistoryPatrolRun.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      sessions: sessions
          .map((item) => HistorySession.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
    );
  }
}

class HistorySession {
  const HistorySession({
    required this.index,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.expectedCount,
    required this.scannedCount,
    required this.missingCheckpointNames,
    required this.scans,
    required this.userId,
    required this.userName,
    this.profilePicture,
  });
  final int index;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final int expectedCount;
  final int scannedCount;
  final List<String> missingCheckpointNames;
  final List<NfcLog> scans;
  final int userId;
  final String userName;
  final String? profilePicture;
  bool get isMissed => status == 'missed';
  bool get isComplete => status == 'complete';
  bool get isInProgress => status == 'in_progress';

  factory HistorySession.fromJson(Map<String, dynamic> json) {
    final missing = json['missingCheckpoints'] as List<dynamic>? ?? const [];
    final scans = json['scans'] as List<dynamic>? ?? const [];
    return HistorySession(
      index: (json['index'] as num).toInt(),
      startAt: DateTime.parse(json['startAt'] as String),
      endAt: DateTime.parse(json['endAt'] as String),
      status: json['status'] as String,
      expectedCount: (json['expectedCount'] as num?)?.toInt() ?? 0,
      scannedCount: (json['scannedCount'] as num?)?.toInt() ?? 0,
      missingCheckpointNames: missing
          .map((item) =>
              (Map<String, dynamic>.from(item as Map))['name'] as String)
          .toList(),
      scans: scans
          .map((item) => NfcLog.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: json['userName'] as String? ?? 'Pengguna',
      profilePicture: json['profilePicture'] as String?,
    );
  }
}
'''
api = replace_once(
    api,
    r'class HistoryDay \{.*?\n\}\n\nclass DepartmentRecord',
    history_models + '\nclass DepartmentRecord',
    'api history models',
    flags=re.S,
)
api = replace_once(
    api,
    r"  Future<HistoryDay> getHistory\(DateTime date\) async => HistoryDay\.fromJson\(.*?\n      \);",
    """  Future<HistoryDay> getHistory(\n    DateTime date, {\n    int? departmentId,\n  }) async =>\n      HistoryDay.fromJson(\n        _decode(\n          await http.get(\n            _uri('/api/scans', {\n              'date': _dateKey(date),\n              if (departmentId != null) 'departmentId': departmentId.toString(),\n            }),\n            headers: _headers(),\n          ),\n        ),\n      );""",
    'api getHistory',
    flags=re.S,
)
api_path.write_text(api, encoding='utf-8')

# 5) Pass the authenticated user into History for role-aware department filter.
dash_path = ROOT / 'lib/features/dashboard/dashboard_screen.dart'
dash = dash_path.read_text(encoding='utf-8')
old = "onTap: () => _open(ClockingHistoryScreen(api: widget.api)),"
new = "onTap: () => _open(ClockingHistoryScreen(api: widget.api, user: _user)),"
if old not in dash:
    raise SystemExit('dashboard history navigation marker not found')
dash = dash.replace(old, new, 1)
dash_path.write_text(dash, encoding='utf-8')

# 6) History UI: Management department picker + archived route viewer.
history_path = ROOT / 'lib/features/history/clocking_history_screen.dart'
history_path.write_text(r'''import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';

class ClockingHistoryScreen extends StatefulWidget {
  const ClockingHistoryScreen({
    required this.api,
    required this.user,
    super.key,
  });

  final ApiService api;
  final AppUser user;

  @override
  State<ClockingHistoryScreen> createState() => _ClockingHistoryScreenState();
}

class _ClockingHistoryScreenState extends State<ClockingHistoryScreen> {
  DateTime _selectedDate = DateTime.now();
  int? _selectedDepartmentId;
  List<DepartmentRecord> _departments = const [];
  late Future<HistoryDay> _future;

  @override
  void initState() {
    super.initState();
    _selectedDepartmentId = widget.user.departmentId;
    _future = widget.user.isManagement
        ? _loadManagementInitial()
        : widget.api.getHistory(_selectedDate);
  }

  Future<HistoryDay> _loadManagementInitial() async {
    final departments = await widget.api.getAdminDepartments();
    final selected = _selectedDepartmentId ??
        (departments.isEmpty ? null : departments.first.id);
    if (mounted) {
      setState(() {
        _departments = departments;
        _selectedDepartmentId = selected;
      });
    }
    if (selected == null) {
      throw const ApiException('Tiada Jabatan tersedia untuk dipaparkan.');
    }
    return widget.api.getHistory(_selectedDate, departmentId: selected);
  }

  void _load(DateTime date, {int? departmentId}) {
    final normalized = DateTime(date.year, date.month, date.day);
    final selected = departmentId ?? _selectedDepartmentId;
    setState(() {
      _selectedDate = normalized;
      if (departmentId != null) _selectedDepartmentId = departmentId;
      _future = widget.api.getHistory(
        normalized,
        departmentId: widget.user.isManagement ? selected : null,
      );
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: 'Pilih tarikh rekod',
    );
    if (picked != null) _load(picked);
  }

  String _formatDate(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sejarah Rondaan'),
        actions: [
          IconButton(
            tooltip: 'Muat semula',
            onPressed: () => _load(_selectedDate),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.user.isManagement) ...[
                        DropdownButtonFormField<int>(
                          initialValue: _selectedDepartmentId,
                          decoration: const InputDecoration(
                            labelText: 'Jabatan',
                            prefixIcon: Icon(Icons.apartment_rounded),
                          ),
                          items: _departments
                              .map(
                                (department) => DropdownMenuItem<int>(
                                  value: department.id,
                                  child: Text(
                                    department.active
                                        ? department.name
                                        : '${department.name} (Tidak aktif)',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _load(_selectedDate, departmentId: value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        'Tarikh: ${_formatDate(_selectedDate)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Hari ini'),
                            selected: _sameDay(_selectedDate, today),
                            onSelected: (_) => _load(today),
                          ),
                          ChoiceChip(
                            label: const Text('Semalam'),
                            selected: _sameDay(_selectedDate, yesterday),
                            onSelected: (_) => _load(yesterday),
                          ),
                          ActionChip(
                            avatar: const Icon(
                              Icons.calendar_month_rounded,
                              size: 18,
                            ),
                            label: const Text('Pilih tarikh'),
                            onPressed: _pickDate,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<HistoryDay>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final history = snapshot.data!;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Text(
                        '${history.department} • Sesi rondaan setiap ${history.sessionIntervalMinutes} minit',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.route_rounded),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pergerakan Rondaan',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          Text('${history.patrolRuns.length} rekod'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (history.patrolRuns.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text(
                              'Tiada rekod mula rondaan atau trail GPS untuk tarikh ini.',
                            ),
                          ),
                        )
                      else
                        ...history.patrolRuns.map(
                          (run) => _PatrolRunCard(
                            run: run,
                            formatTime: _formatTime,
                          ),
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Icon(Icons.fact_check_outlined),
                          const SizedBox(width: 8),
                          Text(
                            'Sesi & Checkpoint',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (history.sessions.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('Tiada sesi rondaan untuk tarikh ini.'),
                          ),
                        )
                      else
                        ...history.sessions.map(
                          (session) => _SessionCard(
                            session: session,
                            formatTime: _formatTime,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatrolRunCard extends StatelessWidget {
  const _PatrolRunCard({required this.run, required this.formatTime});

  final HistoryPatrolRun run;
  final String Function(DateTime) formatTime;

  ImageProvider<Object>? _imageProvider(String? picture) {
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/')) {
      final comma = picture.indexOf(',');
      if (comma > 0) {
        try {
          return MemoryImage(base64Decode(picture.substring(comma + 1)));
        } catch (_) {
          return null;
        }
      }
    }
    return NetworkImage(picture);
  }

  String _duration() {
    final seconds = run.durationSeconds;
    if (seconds == null) return 'Belum tamat';
    final duration = Duration(seconds: seconds);
    if (duration.inHours > 0) {
      return '${duration.inHours}j ${duration.inMinutes % 60}m';
    }
    if (duration.inMinutes > 0) return '${duration.inMinutes} minit';
    return '${duration.inSeconds} saat';
  }

  void _showTrail(BuildContext context) {
    final points = run.trail
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    if (points.isEmpty) return;
    final latitude = points.map((point) => point.latitude).reduce((a, b) => a + b) /
        points.length;
    final longitude = points.map((point) => point.longitude).reduce((a, b) => a + b) /
        points.length;
    final center = LatLng(latitude, longitude);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Text(
                  '${run.userName} • Sesi Rondaan ${run.sessionIndex + 1}\n${formatTime(run.startedAt)} - ${run.endedAt == null ? 'Belum tamat' : formatTime(run.endedAt!)} • ${run.trailPointCount} titik GPS',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: points.length == 1 ? 17 : 16,
                    minZoom: 3,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'dev.rimbakawal.app',
                    ),
                    if (points.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: points,
                            strokeWidth: 5,
                            color: const Color(0xFFFFD54F),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: points.first,
                          width: 52,
                          height: 52,
                          child: const CircleAvatar(
                            backgroundColor: Color(0xFF00B894),
                            child: Icon(Icons.play_arrow_rounded),
                          ),
                        ),
                        if (points.length > 1)
                          Marker(
                            point: points.last,
                            width: 52,
                            height: 52,
                            child: const CircleAvatar(
                              backgroundColor: Color(0xFFC0392B),
                              child: Icon(Icons.stop_rounded),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(
                  'Peta © penyumbang OpenStreetMap • hijau = mula • merah = lokasi akhir trail',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _imageProvider(run.profilePicture);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: image,
                  child: image == null
                      ? Text(run.userName.isEmpty ? '?' : run.userName[0])
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        run.userName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('Sesi Rondaan ${run.sessionIndex + 1}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HistoryChip(
                  icon: Icons.play_circle_outline_rounded,
                  text: 'Mula ${formatTime(run.startedAt)}',
                ),
                _HistoryChip(
                  icon: Icons.stop_circle_outlined,
                  text: run.endedAt == null
                      ? 'Tamat belum direkod'
                      : 'Tamat ${formatTime(run.endedAt!)}',
                ),
                _HistoryChip(
                  icon: Icons.timer_outlined,
                  text: _duration(),
                ),
                _HistoryChip(
                  icon: Icons.route_rounded,
                  text: '${run.trailPointCount} titik GPS',
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: run.trail.isEmpty ? null : () => _showTrail(context),
              icon: const Icon(Icons.map_rounded),
              label: const Text('LIHAT TRAIL RONDAAN'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  const _HistoryChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.formatTime});

  final HistorySession session;
  final String Function(DateTime) formatTime;

  ImageProvider<Object>? _imageProvider(String? picture) {
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/')) {
      final comma = picture.indexOf(',');
      if (comma > 0) {
        try {
          return MemoryImage(base64Decode(picture.substring(comma + 1)));
        } catch (_) {
          return null;
        }
      }
    }
    return NetworkImage(picture);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = session.isMissed
        ? scheme.error
        : session.isComplete
            ? Colors.greenAccent
            : scheme.secondary;
    final statusLabel = switch (session.status) {
      'complete' => 'LENGKAP',
      'missed' => 'CHECKPOINT TERLEPAS',
      'in_progress' => 'SESI SEMASA',
      'no_checkpoints' => 'TIADA CHECKPOINT',
      _ => session.status.toUpperCase(),
    };
    final image = _imageProvider(session.profilePicture);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: session.isMissed
              ? scheme.error.withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.08),
          width: session.isMissed ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: image,
                  child: image == null
                      ? Text(session.userName.isEmpty ? '?' : session.userName[0])
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session.userName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sesi Rondaan ${session.index + 1} • ${formatTime(session.startAt)} - ${formatTime(session.endAt)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${session.scannedCount}/${session.expectedCount} checkpoint direkodkan'),
            if (session.missingCheckpointNames.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (session.isMissed ? scheme.error : scheme.secondary)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${session.isMissed ? 'TERLEPAS' : 'Belum diimbas'}: ${session.missingCheckpointNames.join(', ')}',
                  style: TextStyle(
                    color: session.isMissed ? scheme.error : null,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            if (session.scans.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...session.scans.map(
                (scan) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.nfc_rounded),
                  title: Text(scan.checkpointName ?? 'Checkpoint tidak dikenal pasti'),
                  subtitle: Text(
                    '${scan.userName ?? session.userName} • ${scan.nfcUid} • ${formatTime(scan.scannedAt)}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
''', encoding='utf-8')

print('Patrol history trail + management department upgrade applied.')
