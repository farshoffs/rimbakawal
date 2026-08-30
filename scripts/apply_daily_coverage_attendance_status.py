from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Missing expected block: {label}')
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, label: str, flags=0) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f'Expected exactly one match for {label}, got {count}')
    return updated

# 1) Remove duplicate NFC settings entry from Dashboard. It remains in Pentadbiran.
dashboard_path = Path('lib/features/dashboard/dashboard_screen.dart')
dashboard = dashboard_path.read_text()
dashboard = dashboard.replace("import '../settings/nfc_settings_screen.dart';\n", '')
dashboard = regex_once(
    dashboard,
    r"\n  void _openNfcSettings\(\) =>\s*\n\s*_open\(NfcSettingsScreen\(mockMode: widget\.mockMode\)\);\n",
    "\n",
    'dashboard NFC settings opener',
)
dashboard = regex_once(
    dashboard,
    r"\n\s*_MenuData\(\n\s*icon: nfcTestMode\n\s*\? Icons\.science_rounded\n\s*: Icons\.nfc_rounded,\n\s*title: 'Tetapan NFC',\n\s*subtitle: nfcTestMode\n\s*\? 'Mod Test NFC aktif'\n\s*: 'Mod Scan NFC Sebenar aktif',\n\s*onTap: _openNfcSettings,\n\s*\),",
    "",
    'dashboard NFC settings card',
)
dashboard_path.write_text(dashboard)

# 2) Command center server calculations: calendar day in Malaysia + one patrol coverage per department/session.
app_path = Path('worker/app.js')
app = app_path.read_text()
app = replace_once(
    app,
    """  const now = new Date();
  const bounds = {
    startIso: new Date(now.getTime() - 86400000).toISOString(),
    endIso: new Date(now.getTime() + 60000).toISOString(),
  };
""",
    """  const now = new Date();
  const todayKey = malaysiaDateKey(now);
  const todayBounds = malaysiaDayBounds(todayKey);
  const bounds = {
    startIso: todayBounds.startIso,
    endIso: todayBounds.endIso,
  };
""",
    'command center calendar bounds',
)
app = replace_once(
    app,
    """    patrols.push({
      userId: Number(user.id),
      nama: user.nama,
""",
    """    patrols.push({
      userId: Number(user.id),
      departmentId: Number(user.department_id || 0),
      nama: user.nama,
""",
    'patrol department id',
)
aggregate = r'''

  // Liputan rondaan dikira sekali bagi setiap Jabatan/sesi, bukan sekali bagi
  // setiap pengawal. Hanya sesi yang SUDAH TAMAT pada tarikh kalendar Malaysia
  // hari semasa dikira sebagai due/terlepas. Sesi akan datang tidak disentuh.
  completeCount = 0;
  alertCount = 0;
  missedSessionCount = 0;
  missedCheckpointCount = 0;
  scannedCheckpointCount = 0;
  dueCheckpointCount = 0;
  completedScannedCheckpointCount = 0;

  const departmentUsers = new Map();
  for (const user of usersResult.results ?? []) {
    const departmentId = Number(user.department_id || 0);
    if (departmentId <= 0) continue;
    const list = departmentUsers.get(departmentId) ?? [];
    list.push(user);
    departmentUsers.set(departmentId, list);
  }

  for (const [departmentId, users] of departmentUsers.entries()) {
    const sample = users[0];
    const interval = Math.max(15, Number(sample.session_interval_minutes || 120));
    const intervalMs = interval * 60000;
    const sessionStartMinutes = Math.max(0, Math.min(1439, Number(sample.session_start_minutes ?? 420)));
    const expected = checkpointCounts.get(departmentId) ?? 0;
    if (expected <= 0) continue;

    const anchorMs = todayBounds.startMs + sessionStartMinutes * 60000;
    const nowMs = now.getTime();
    const userIds = new Set(users.map((user) => Number(user.id)));
    const departmentScans = scans.filter((row) => {
      const time = Date.parse(row.scanned_at);
      return userIds.has(Number(row.user_id))
        && time >= todayBounds.startMs
        && time < todayBounds.endMs;
    });

    // Belum sampai jam mula rondaan hari ini: tiada sesi yang due atau terlepas.
    if (nowMs < anchorMs) continue;

    const currentIndex = Math.floor((nowMs - anchorMs) / intervalMs);
    const currentStartMs = anchorMs + currentIndex * intervalMs;
    const currentEndMs = Math.min(todayBounds.endMs, currentStartMs + intervalMs);

    // Sesi sebelum currentIndex telah tamat dan sahaja yang boleh dianggap due.
    for (let index = 0; index < currentIndex; index += 1) {
      const sessionStartMs = anchorMs + index * intervalMs;
      if (sessionStartMs >= todayBounds.endMs) break;
      const sessionEndMs = Math.min(todayBounds.endMs, sessionStartMs + intervalMs);
      if (sessionEndMs > nowMs) break;
      const unique = new Set(
        departmentScans
          .filter((row) => {
            const time = Date.parse(row.scanned_at);
            return time >= sessionStartMs && time < sessionEndMs;
          })
          .map((row) => Number(row.checkpoint_id))
          .filter((id) => id > 0),
      );
      dueCheckpointCount += expected;
      completedScannedCheckpointCount += unique.size;
      scannedCheckpointCount += unique.size;
      if (unique.size < expected) {
        missedSessionCount += 1;
        missedCheckpointCount += expected - unique.size;
      }
    }

    // Sesi semasa dipaparkan untuk kemajuan, tetapi tidak dianggap terlepas.
    if (currentStartMs < todayBounds.endMs && nowMs < currentEndMs) {
      const currentUnique = new Set(
        departmentScans
          .filter((row) => {
            const time = Date.parse(row.scanned_at);
            return time >= currentStartMs && time < currentEndMs;
          })
          .map((row) => Number(row.checkpoint_id))
          .filter((id) => id > 0),
      );
      scannedCheckpointCount += currentUnique.size;
      if (currentUnique.size >= expected) completeCount += 1;

      const hasActivePatroller = users.some((user) => activePatrols.has(Number(user.id)));
      const minutesIntoSession = Math.max(0, Math.floor((nowMs - currentStartMs) / 60000));
      const grace = Math.max(10, Math.min(30, Math.floor(interval / 4)));
      if (hasActivePatroller && minutesIntoSession >= grace && currentUnique.size === 0) {
        alertCount += 1;
      }
    }
  }
'''
app = replace_once(
    app,
    """  const incidents = incidentsResult.results ?? [];
""",
    aggregate + "\n  const incidents = incidentsResult.results ?? [];\n",
    'department coverage aggregation',
)
app = replace_once(
    app,
    """      alerts: alertCount,
      missedSessions: missedSessionCount,
""",
    """      alerts: alertCount,
      coverageDate: todayKey,
      missedSessions: missedSessionCount,
""",
    'coverage date summary',
)
app_path.write_text(app)

# 3) Decorate patrol rows with current attendance and choose only one session patroller per department.
attendance_path = Path('worker/attendance.js')
attendance = attendance_path.read_text()
present_block = r'''
  const presentResult = await env.DB.prepare(
    `SELECT a.user_id, a.department_id, a.punched_at
     FROM attendance_records a
     JOIN users u ON u.id = a.user_id
     JOIN (
       SELECT user_id, MAX(punched_at) AS max_time
       FROM attendance_records
       WHERE work_date = ? ${scopeDepartment ? 'AND department_id = ?' : ''}
       GROUP BY user_id
     ) latest ON latest.user_id = a.user_id AND latest.max_time = a.punched_at
     WHERE a.work_date = ? ${scopeDepartment ? 'AND a.department_id = ?' : ''}
       AND a.punch_type = 'IN'
       AND u.active = 1
       AND LOWER(u.jawatan) IN ('patrol', 'supervisor')`,
  ).bind(...(scopeDepartment
    ? [date, scopeDepartment, date, scopeDepartment]
    : [date, date])).all();

  const presentByUser = new Map(
    (presentResult.results ?? []).map((row) => [Number(row.user_id), row]),
  );
  const rows = (payload.patrols ?? []).map((row) => ({
    ...row,
    present: presentByUser.has(Number(row.userId)),
    attendanceAt: presentByUser.get(Number(row.userId))?.punched_at ?? null,
    isSessionPatroller: false,
  }));

  // Walaupun beberapa peranti tersilap memulakan rondaan serentak, paparan Status
  // Pengawal hanya memilih seorang peronda untuk setiap Jabatan bagi sesi semasa.
  const chosenByDepartment = new Map();
  for (const row of rows) {
    if (!row.present) continue;
    if (Number(row.scannedCount || 0) <= 0 && row.patrolSessionId == null) continue;
    const departmentId = Number(row.departmentId || 0);
    if (departmentId <= 0) continue;
    const stamp = Math.max(
      Date.parse(row.lastScanAt || '') || 0,
      Date.parse(row.sessionStartedAt || '') || 0,
    );
    const existing = chosenByDepartment.get(departmentId);
    if (!existing || stamp > existing.stamp) {
      chosenByDepartment.set(departmentId, { userId: Number(row.userId), stamp });
    }
  }
  payload.patrols = rows.map((row) => ({
    ...row,
    isSessionPatroller:
      chosenByDepartment.get(Number(row.departmentId || 0))?.userId === Number(row.userId),
  }));
'''
attendance = replace_once(
    attendance,
    """  payload.attendanceRecent = (recentResult.results ?? []).map((row) => ({
    id: Number(row.id),
    userId: Number(row.user_id),
    userName: row.nama,
    department: row.department_name,
    punchType: row.punch_type,
    punchedAt: row.punched_at,
    distanceMeters: Number(row.distance_m || 0),
    faceStatus: row.face_status,
    faceScore: row.face_score == null ? null : Number(row.face_score),
  }));
  return json(payload);
""",
    """  payload.attendanceRecent = (recentResult.results ?? []).map((row) => ({
    id: Number(row.id),
    userId: Number(row.user_id),
    userName: row.nama,
    department: row.department_name,
    punchType: row.punch_type,
    punchedAt: row.punched_at,
    distanceMeters: Number(row.distance_m || 0),
    faceStatus: row.face_status,
    faceScore: row.face_score == null ? null : Number(row.face_score),
  }));
""" + present_block + "\n  return json(payload);\n",
    'current attendance decoration',
)
attendance_path.write_text(attendance)

# 4) Command Center UI: Status Pengawal shows only currently present guards.
command_path = Path('lib/features/admin/command_center_screen.dart')
command = command_path.read_text()
command = command.replace("  String _filter = 'all';\n", '')
command = regex_once(
    command,
    r"  List<Map<String, dynamic>> get _filteredPatrols \{.*?\n  \}\n\n",
    """  List<Map<String, dynamic>> get _filteredPatrols =>
      (_data?.patrols ?? const <Map<String, dynamic>>[])
          .where((row) => row['present'] == true)
          .toList();

""",
    'present guard filter',
    flags=re.S,
)
command = regex_once(
    command,
    r"  Color _statusColor\(String status\) => switch \(status\) \{.*?\n  \};\n\n  String _statusLabel\(String status\) => switch \(status\) \{.*?\n  \};\n\n",
    "",
    'old patrol status helpers',
    flags=re.S,
)
command = replace_once(
    command,
    """                    _SectionHeader(
                      title: 'Status Pengawal',
                      subtitle:
                          '${data?.patrols.length ?? 0} pengguna dipantau',
                    ),
""",
    """                    _SectionHeader(
                      title: 'Status Pengawal • Hadir',
                      subtitle: '${patrols.length} pengawal sedang hadir',
                    ),
""",
    'status guard heading',
)
command = regex_once(
    command,
    r"                    const SizedBox\(height: 10\),\n                    SingleChildScrollView\(\n                      scrollDirection: Axis\.horizontal,\n                      child: SegmentedButton<String>\(.*?\n                    \),\n                    const SizedBox\(height: 12\),",
    """                    const SizedBox(height: 12),""",
    'status segmented filters',
    flags=re.S,
)
command = command.replace(
    "text: 'Tiada pengawal dalam kategori ini.',",
    "text: 'Tiada pengawal yang sedang hadir.',",
)
# Replace both mobile and grid PatrolCard call color/label/time expressions.
command = regex_once(
    command,
    r"color: _statusColor\(\n\s*row\['status'\] as String\? \?\? 'waiting',\n\s*\),\n\s*label: _statusLabel\(\n\s*row\['status'\] as String\? \?\? 'waiting',\n\s*\),\n\s*time: _time\(row\['lastScanAt'\]\),",
    """color: row['isSessionPatroller'] == true
                                            ? const Color(0xFF6C5CE7)
                                            : const Color(0xFF00B894),
                                        label: row['isSessionPatroller'] == true
                                            ? 'PERONDA SESI'
                                            : 'HADIR',
                                        time: _time(row['attendanceAt']),""",
    'mobile present guard card',
    flags=re.S,
)
command = regex_once(
    command,
    r"color: _statusColor\(\n\s*row\['status'\] as String\? \?\? 'waiting',\n\s*\),\n\s*label: _statusLabel\(\n\s*row\['status'\] as String\? \?\? 'waiting',\n\s*\),\n\s*time: _time\(row\['lastScanAt'\]\),",
    """color: row['isSessionPatroller'] == true
                                      ? const Color(0xFF6C5CE7)
                                      : const Color(0xFF00B894),
                                  label: row['isSessionPatroller'] == true
                                      ? 'PERONDA SESI'
                                      : 'HADIR',
                                  time: _time(row['attendanceAt']),""",
    'grid present guard card',
    flags=re.S,
)
# Coverage description and zero-due behavior.
command = replace_once(
    command,
    """    final coverage = due <= 0 ? 1.0 : (completedScanned / due).clamp(0.0, 1.0);
    final coveragePercent = (coverage * 100).round();
""",
    """    final coverage = due <= 0 ? 0.0 : (completedScanned / due).clamp(0.0, 1.0);
    final coveragePercent = (coverage * 100).round();
    final coverageDate = summary['coverageDate'] as String?;
    final dateParts = coverageDate?.split('-') ?? const <String>[];
    final dateLabel = dateParts.length == 3
        ? '${dateParts[2]}/${dateParts[1]}/${dateParts[0]}'
        : 'hari semasa';
""",
    'coverage zero due handling',
)
command = replace_once(
    command,
    """                Chip(label: Text('$coveragePercent% LIPUTAN')),
""",
    """                Chip(
                  label: Text(
                    due <= 0 ? 'BELUM ADA SESI TAMAT' : '$coveragePercent% LIPUTAN',
                  ),
                ),
""",
    'coverage chip',
)
command = replace_once(
    command,
    """            const Text(
              'Sesi yang telah tamat sahaja dikira sebagai terlepas. Sesi semasa tidak dihukum sebelum waktunya tamat.',
            ),
""",
    """            Text(
              'Dikira untuk tarikh $dateLabel sahaja (waktu Malaysia), bukan 24 jam bergerak. Hanya sesi yang telah tamat dikira; sesi semasa dan sesi akan datang tidak dianggap terlepas.',
            ),
""",
    'coverage explanation',
)
# Patrol card becomes attendance-first. Only the single chosen patroller shows progress.
command = replace_once(
    command,
    """    final progress = expected == 0 ? 0.0 : scanned / expected;
    final missed = (row['missedSessions'] as num?)?.toInt() ?? 0;
    final missedCheckpoints = (row['missedCheckpoints'] as num?)?.toInt() ?? 0;
    final scannedToday = (row['scannedToday'] as num?)?.toInt() ?? 0;
""",
    """    final progress = expected == 0 ? 0.0 : scanned / expected;
    final isSessionPatroller = row['isSessionPatroller'] == true;
""",
    'patrol card attendance vars',
)
command = replace_once(
    command,
    """                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 7,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$scanned/$expected checkpoint sesi semasa • imbasan terakhir $time',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Hari ini: $scannedToday diimbas • $missedCheckpoints checkpoint terlepas • $missed sesi terlepas',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
""",
    """                  const SizedBox(height: 8),
                  if (isSessionPatroller) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0, 1),
                        minHeight: 7,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$scanned/$expected checkpoint sesi semasa • hadir sejak $time',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else
                    Text(
                      'Hadir sejak $time',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
""",
    'attendance first patrol card body',
)
command_path.write_text(command)

# 5) Version bump for this behavior change.
pubspec_path = Path('pubspec.yaml')
pubspec = pubspec_path.read_text()
pubspec = replace_once(pubspec, 'version: 0.5.3+19', 'version: 0.5.4+20', 'version bump')
pubspec_path.write_text(pubspec)

print('Applied daily coverage + attendance status refinement.')
