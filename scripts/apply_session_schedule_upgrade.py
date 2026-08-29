from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text()


def write(path: str, text: str) -> None:
    Path(path).write_text(text)


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


# Database: sessions are anchored per department. 07:00 is the safe default;
# each department can change this to e.g. 08:00 in Admin.
Path("migrations/0009_department_session_start.sql").write_text(
    "ALTER TABLE departments ADD COLUMN session_start_minutes INTEGER NOT NULL DEFAULT 420 "
    "CHECK (session_start_minutes BETWEEN 0 AND 1439);\n"
)

# AppUser carries the setting immediately after authentication.
p = "lib/core/api/app_user.dart"
t = read(p)
t = once(
    t,
    "    required this.sessionIntervalMinutes,\n    this.active = true,",
    "    required this.sessionIntervalMinutes,\n    this.sessionStartMinutes = 420,\n    this.active = true,",
    "app user ctor",
)
t = once(
    t,
    "  final int sessionIntervalMinutes;\n  final bool active;",
    "  final int sessionIntervalMinutes;\n  final int sessionStartMinutes;\n  final bool active;",
    "app user field",
)
t = once(
    t,
    "      sessionIntervalMinutes:\n          (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,\n      active:",
    "      sessionIntervalMinutes:\n          (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,\n      sessionStartMinutes:\n          (json['sessionStartMinutes'] as num?)?.toInt() ?? 420,\n      active:",
    "app user parse",
)
write(p, t)

# Offline bootstrap persists schedule settings for disconnected patrols.
p = "lib/core/offline/offline_models.dart"
t = read(p)
t = once(
    t,
    "    required this.sessionIntervalMinutes,\n    required this.routeOrderEnforced,",
    "    required this.sessionIntervalMinutes,\n    this.sessionStartMinutes = 420,\n    required this.routeOrderEnforced,",
    "offline ctor",
)
t = once(
    t,
    "  final int sessionIntervalMinutes;\n  final bool routeOrderEnforced;",
    "  final int sessionIntervalMinutes;\n  final int sessionStartMinutes;\n  final bool routeOrderEnforced;",
    "offline field",
)
t = once(
    t,
    "          'sessionIntervalMinutes': sessionIntervalMinutes,\n          'routeOrderEnforced': routeOrderEnforced,",
    "          'sessionIntervalMinutes': sessionIntervalMinutes,\n          'sessionStartMinutes': sessionStartMinutes,\n          'routeOrderEnforced': routeOrderEnforced,",
    "offline json",
)
t = once(
    t,
    "      sessionIntervalMinutes:\n          (department['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,\n      routeOrderEnforced:",
    "      sessionIntervalMinutes:\n          (department['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,\n      sessionStartMinutes:\n          (department['sessionStartMinutes'] as num?)?.toInt() ?? 420,\n      routeOrderEnforced:",
    "offline parse",
)
write(p, t)

# API models + department CRUD payloads.
p = "lib/core/api/api_service.dart"
t = read(p)
t = once(
    t,
    "    required this.sessionIntervalMinutes,\n    required this.active,",
    "    required this.sessionIntervalMinutes,\n    this.sessionStartMinutes = 420,\n    required this.active,",
    "department ctor",
)
t = once(
    t,
    "  final int sessionIntervalMinutes;\n  final bool active;",
    "  final int sessionIntervalMinutes;\n  final int sessionStartMinutes;\n  final bool active;",
    "department field",
)
t = once(
    t,
    "        sessionIntervalMinutes:\n            (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,\n        active:",
    "        sessionIntervalMinutes:\n            (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,\n        sessionStartMinutes:\n            (json['sessionStartMinutes'] as num?)?.toInt() ?? 420,\n        active:",
    "department parse",
)
t = once(
    t,
    "  Future<DepartmentRecord> createDepartment({\n    required String name,\n    required int sessionIntervalMinutes,\n  }) async {",
    "  Future<DepartmentRecord> createDepartment({\n    required String name,\n    required int sessionIntervalMinutes,\n    int sessionStartMinutes = 420,\n  }) async {",
    "create department signature",
)
t = once(
    t,
    "          'name': name,\n          'sessionIntervalMinutes': sessionIntervalMinutes,\n        }),",
    "          'name': name,\n          'sessionIntervalMinutes': sessionIntervalMinutes,\n          'sessionStartMinutes': sessionStartMinutes,\n        }),",
    "create department payload",
)
t = once(
    t,
    "          'sessionIntervalMinutes': department.sessionIntervalMinutes,\n          'active': department.active,",
    "          'sessionIntervalMinutes': department.sessionIntervalMinutes,\n          'sessionStartMinutes': department.sessionStartMinutes,\n          'active': department.active,",
    "update department payload",
)
write(p, t)

# Admin setting: visible start time + time picker.
p = "lib/features/admin/department_maintenance_screen.dart"
t = read(p)
t = once(
    t,
    "                    'Sesi setiap ${department.sessionIntervalMinutes} minit • '\n                    '${department.checkpointCount} checkpoint aktif'",
    "                    'Mula ${TimeOfDay(hour: department.sessionStartMinutes ~/ 60, minute: department.sessionStartMinutes % 60).format(context)} • '\n                    'Sesi setiap ${department.sessionIntervalMinutes} minit • '\n                    '${department.checkpointCount} checkpoint aktif'",
    "department subtitle",
)
t = once(
    t,
    "  late final TextEditingController _intervalController;\n  late bool _active;",
    "  late final TextEditingController _intervalController;\n  late TimeOfDay _startTime;\n  late bool _active;",
    "start time field",
)
t = once(
    t,
    "    _intervalController = TextEditingController(\n      text: (widget.department?.sessionIntervalMinutes ?? 120).toString(),\n    );\n    _active = widget.department?.active ?? true;",
    "    _intervalController = TextEditingController(\n      text: (widget.department?.sessionIntervalMinutes ?? 120).toString(),\n    );\n    final startMinutes = widget.department?.sessionStartMinutes ?? 420;\n    _startTime = TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);\n    _active = widget.department?.active ?? true;",
    "start time init",
)
marker = "  Future<void> _save() async {\n"
picker = """  Future<void> _pickStartTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _startTime,
      helpText: 'Jam mula sesi rondaan',
    );
    if (selected != null && mounted) setState(() => _startTime = selected);
  }

"""
if marker not in t:
    raise RuntimeError("department save marker missing")
t = t.replace(marker, picker + marker, 1)
t = once(
    t,
    "    final interval = int.tryParse(_intervalController.text.trim());\n    if (name.length < 2 || interval == null) {",
    "    final interval = int.tryParse(_intervalController.text.trim());\n    final startMinutes = _startTime.hour * 60 + _startTime.minute;\n    if (name.length < 2 || interval == null) {",
    "save start minutes",
)
t = once(
    t,
    "          name: name,\n          sessionIntervalMinutes: interval,\n        );",
    "          name: name,\n          sessionIntervalMinutes: interval,\n          sessionStartMinutes: startMinutes,\n        );",
    "create start payload ui",
)
t = once(
    t,
    "            sessionIntervalMinutes: interval,\n            active: _active,",
    "            sessionIntervalMinutes: interval,\n            sessionStartMinutes: startMinutes,\n            active: _active,",
    "update start payload ui",
)
t = once(
    t,
    "              TextField(\n                controller: _intervalController,\n                keyboardType: TextInputType.number,\n                decoration: const InputDecoration(\n                  labelText: 'Tempoh satu sesi (minit)',\n                  helperText: 'Default: 120 minit (2 jam)',\n                  prefixIcon: Icon(Icons.timer_outlined),\n                ),\n              ),\n              if (widget.department != null) ...[",
    "              TextField(\n                controller: _intervalController,\n                keyboardType: TextInputType.number,\n                decoration: const InputDecoration(\n                  labelText: 'Tempoh satu sesi (minit)',\n                  helperText: 'Default: 120 minit (2 jam)',\n                  prefixIcon: Icon(Icons.timer_outlined),\n                ),\n              ),\n              const SizedBox(height: 14),\n              ListTile(\n                contentPadding: const EdgeInsets.symmetric(horizontal: 4),\n                leading: const Icon(Icons.schedule_rounded),\n                title: const Text('Jam mula rondaan'),\n                subtitle: Text('Sesi 1 bermula pada ${_startTime.format(context)}'),\n                trailing: FilledButton.tonal(\n                  onPressed: _pickStartTime,\n                  child: Text(_startTime.format(context)),\n                ),\n              ),\n              if (widget.department != null) ...[",
    "time picker ui",
)
write(p, t)

# Base Worker: auth metadata, history, direct scan and department CRUD.
p = "worker/index.js"
t = read(p)
t = t.replace(
    "COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes",
    "COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,\n                 COALESCE(d.session_start_minutes, 420) AS session_start_minutes",
)
t = t.replace(
    "`SELECT d.id, d.name, d.session_interval_minutes, d.active,",
    "`SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,",
)
t = once(
    t,
    "      sessionIntervalMinutes: Number(auth.user.session_interval_minutes || 120),\n    },",
    "      sessionIntervalMinutes: Number(auth.user.session_interval_minutes || 120),\n      sessionStartMinutes: Number(auth.user.session_start_minutes ?? 420),\n    },",
    "patrol config start",
)
t = once(
    t,
    "  const bounds = malaysiaDayBounds(requestedDate);\n  if (!bounds) return json({ error: 'Tarikh tidak sah.' }, 400);",
    "  const calendarBounds = malaysiaDayBounds(requestedDate);\n  if (!calendarBounds) return json({ error: 'Tarikh tidak sah.' }, 400);\n  const sessionStartMinutes = Math.max(0, Math.min(1439, Number(auth.user.session_start_minutes ?? 420)));\n  const bounds = {\n    startMs: calendarBounds.startMs + sessionStartMinutes * 60000,\n    endMs: calendarBounds.startMs + sessionStartMinutes * 60000 + 86400000,\n  };\n  bounds.startIso = new Date(bounds.startMs).toISOString();\n  bounds.endIso = new Date(bounds.endMs).toISOString();",
    "history bounds",
)
t = once(
    t,
    "  const todayKey = malaysiaDateKey(new Date());",
    "  const todayKey = scheduleDateKey(new Date(), sessionStartMinutes);",
    "history today key",
)
t = once(
    t,
    "    sessionIntervalMinutes: interval,\n    checkpoints,",
    "    sessionIntervalMinutes: interval,\n    sessionStartMinutes,\n    checkpoints,",
    "history response start",
)
t = once(
    t,
    "  const malaysiaNow = new Date(Date.now() + MALAYSIA_OFFSET_MS);\n  const minuteOfDay = malaysiaNow.getUTCHours() * 60 + malaysiaNow.getUTCMinutes();\n  const sessionIndex = Math.floor(minuteOfDay / interval);",
    "  const sessionIndex = currentSessionIndex(new Date(), interval, auth.user.session_start_minutes);",
    "direct scan index",
)
t = once(
    t,
    "  const interval = Number(body.sessionIntervalMinutes ?? 120);\n  const validation = validateDepartment(name, interval);",
    "  const interval = Number(body.sessionIntervalMinutes ?? 120);\n  const startMinutes = Number(body.sessionStartMinutes ?? 420);\n  const validation = validateDepartment(name, interval, startMinutes);",
    "create validation",
)
t = once(
    t,
    "`INSERT INTO departments (name, session_interval_minutes, active, updated_at)\n     VALUES (?, ?, 1, CURRENT_TIMESTAMP)`,\n  ).bind(name, interval).run();",
    "`INSERT INTO departments (name, session_interval_minutes, session_start_minutes, active, updated_at)\n     VALUES (?, ?, ?, 1, CURRENT_TIMESTAMP)`,\n  ).bind(name, interval, startMinutes).run();",
    "create department sql",
)
t = once(
    t,
    "  const interval = Number(body.sessionIntervalMinutes ?? 120);\n  const active = body.active === false ? 0 : 1;\n  const validation = validateDepartment(name, interval);",
    "  const interval = Number(body.sessionIntervalMinutes ?? 120);\n  const startMinutes = Number(body.sessionStartMinutes ?? 420);\n  const active = body.active === false ? 0 : 1;\n  const validation = validateDepartment(name, interval, startMinutes);",
    "update validation",
)
t = once(
    t,
    "       SET name = ?, session_interval_minutes = ?, active = ?, updated_at = CURRENT_TIMESTAMP\n       WHERE id = ?`,\n    ).bind(name, interval, active, departmentId),",
    "       SET name = ?, session_interval_minutes = ?, session_start_minutes = ?, active = ?, updated_at = CURRENT_TIMESTAMP\n       WHERE id = ?`,\n    ).bind(name, interval, startMinutes, active, departmentId),",
    "update department sql",
)
t = once(
    t,
    "    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),\n    active:",
    "    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),\n    sessionStartMinutes: Number(user.session_start_minutes ?? 420),\n    active:",
    "public user start",
)
t = once(
    t,
    "    sessionIntervalMinutes: Number(row.session_interval_minutes || 120),\n    active:",
    "    sessionIntervalMinutes: Number(row.session_interval_minutes || 120),\n    sessionStartMinutes: Number(row.session_start_minutes ?? 420),\n    active:",
    "department json start",
)
t = once(
    t,
    "function validateDepartment(name, interval) {\n  if (name.length < 2 || name.length > 150) return 'Nama Jabatan mesti antara 2 hingga 150 aksara.';\n  if (!Number.isInteger(interval) || interval < 15 || interval > 1440) {\n    return 'Tempoh sesi mesti antara 15 hingga 1440 minit.';\n  }\n  return null;\n}",
    "function validateDepartment(name, interval, startMinutes) {\n  if (name.length < 2 || name.length > 150) return 'Nama Jabatan mesti antara 2 hingga 150 aksara.';\n  if (!Number.isInteger(interval) || interval < 15 || interval > 1440) {\n    return 'Tempoh sesi mesti antara 15 hingga 1440 minit.';\n  }\n  if (!Number.isInteger(startMinutes) || startMinutes < 0 || startMinutes > 1439) {\n    return 'Jam mula rondaan tidak sah.';\n  }\n  return null;\n}",
    "validate department",
)
helper_marker = "function malaysiaDateKey(date) {\n"
helpers = """function scheduleDayWindow(value, startMinutes = 420) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  const safeStart = Math.max(0, Math.min(1439, Number(startMinutes ?? 420)));
  const localMidnightUtc = Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate());
  let startMs = localMidnightUtc - MALAYSIA_OFFSET_MS + safeStart * 60000;
  if (minuteOfDay < safeStart) startMs -= 86400000;
  return { startMs, endMs: startMs + 86400000 };
}

function currentSessionIndex(value, interval, startMinutes = 420) {
  const day = scheduleDayWindow(value, startMinutes);
  const safeInterval = Math.max(15, Math.min(1440, Number(interval || 120)));
  return Math.floor((value.getTime() - day.startMs) / 60000 / safeInterval);
}

function scheduleDateKey(value, startMinutes = 420) {
  const day = scheduleDayWindow(value, startMinutes);
  return malaysiaDateKey(new Date(day.startMs));
}

"""
if helper_marker not in t:
    raise RuntimeError("index helper marker missing")
t = t.replace(helper_marker, helpers + helper_marker, 1)
write(p, t)

# Smart Worker: live patrol config/scan and command center use the same anchor.
p = "worker/app.js"
t = read(p)
t = t.replace(
    "COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes",
    "COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,\n            COALESCE(d.session_start_minutes, 420) AS session_start_minutes",
)
t = t.replace(
    "SELECT id, name, session_interval_minutes, route_order_enforced",
    "SELECT id, name, session_interval_minutes, session_start_minutes, route_order_enforced",
)
t = t.replace(
    "SELECT id, session_interval_minutes, route_order_enforced",
    "SELECT id, session_interval_minutes, session_start_minutes, route_order_enforced",
)
if "currentSessionIndex(now, interval)" not in t:
    raise RuntimeError("start patrol session index marker missing")
t = t.replace(
    "currentSessionIndex(now, interval)",
    "currentSessionIndex(now, interval, auth.user.session_start_minutes)",
    1,
)
old_block = """  const interval = Number(department.session_interval_minutes || 120);
  const now = new Date();
  const day = malaysiaDayBounds(malaysiaDateKey(now));
  const sessionIndex = currentSessionIndex(now, interval);
  const sessionStart = day.startMs + sessionIndex * interval * 60000;
  const sessionEnd = Math.min(day.endMs, sessionStart + interval * 60000);"""
new_block = """  const interval = Number(department.session_interval_minutes || 120);
  const now = new Date();
  const window = sessionWindow(now, interval, department.session_start_minutes);
  const sessionIndex = window.index;
  const sessionStart = window.startMs;
  const sessionEnd = window.endMs;"""
if t.count(old_block) != 2:
    raise RuntimeError(f"smart session blocks: expected 2, got {t.count(old_block)}")
t = t.replace(old_block, new_block)
t = once(
    t,
    "      sessionIntervalMinutes: interval,\n      routeOrderEnforced:",
    "      sessionIntervalMinutes: interval,\n      sessionStartMinutes: Number(department.session_start_minutes ?? 420),\n      routeOrderEnforced:",
    "smart config response",
)
t = once(
    t,
    "  const today = malaysiaDateKey(now);\n  const bounds = malaysiaDayBounds(today);",
    "  const bounds = {\n    startIso: new Date(now.getTime() - 86400000).toISOString(),\n    endIso: new Date(now.getTime() + 60000).toISOString(),\n  };",
    "command center scan bounds",
)
t = once(
    t,
    """    const interval = Number(user.session_interval_minutes || 120);
    const currentIndex = currentSessionIndex(now, interval);
    const expected = checkpointCounts.get(Number(user.department_id)) ?? 0;
    const currentScans = scans.filter((row) =>
      Number(row.user_id) === Number(user.id) && Number(row.session_index) === currentIndex
    );
    const uniqueCurrent = new Set(currentScans.map((row) => Number(row.checkpoint_id)).filter((id) => id > 0));
    const lastScan = scans.filter((row) => Number(row.user_id) === Number(user.id)).at(-1) ?? null;""",
    """    const interval = Number(user.session_interval_minutes || 120);
    const sessionStartMinutes = Number(user.session_start_minutes ?? 420);
    const currentWindow = sessionWindow(now, interval, sessionStartMinutes);
    const currentIndex = currentWindow.index;
    const scheduleDay = scheduleDayWindow(now, sessionStartMinutes);
    const expected = checkpointCounts.get(Number(user.department_id)) ?? 0;
    const userDayScans = scans.filter((row) => {
      const time = Date.parse(row.scanned_at);
      return Number(row.user_id) === Number(user.id) && time >= scheduleDay.startMs && time < scheduleDay.endMs;
    });
    const currentScans = userDayScans.filter((row) => {
      const time = Date.parse(row.scanned_at);
      return time >= currentWindow.startMs && time < currentWindow.endMs;
    });
    const uniqueCurrent = new Set(currentScans.map((row) => Number(row.checkpoint_id)).filter((id) => id > 0));
    const lastScan = userDayScans.at(-1) ?? null;""",
    "command center current scans",
)
t = once(
    t,
    "const unique = new Set(scans\n        .filter((row) => Number(row.user_id) === Number(user.id) && Number(row.session_index) === index)",
    "const unique = new Set(userDayScans\n        .filter((row) => Number(row.session_index) === index)",
    "command center missed scans",
)
t = once(
    t,
    """    const shifted = new Date(now.getTime() + MALAYSIA_OFFSET_MS);
    const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
    const minutesIntoSession = minuteOfDay - currentIndex * interval;""",
    "    const minutesIntoSession = Math.max(0, Math.floor((now.getTime() - currentWindow.startMs) / 60000));",
    "command center minutes into session",
)
t = once(
    t,
    "    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),\n  };",
    "    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),\n    sessionStartMinutes: Number(user.session_start_minutes ?? 420),\n  };",
    "app public user start",
)
t = once(
    t,
    """function currentSessionIndex(value, interval) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  return Math.floor(minuteOfDay / Math.max(15, Math.min(1440, interval)));
}""",
    """function scheduleDayWindow(value, startMinutes = 420) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  const safeStart = Math.max(0, Math.min(1439, Number(startMinutes ?? 420)));
  const localMidnightUtc = Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate());
  let startMs = localMidnightUtc - MALAYSIA_OFFSET_MS + safeStart * 60000;
  if (minuteOfDay < safeStart) startMs -= 86400000;
  return { startMs, endMs: startMs + 86400000 };
}

function sessionWindow(value, interval, startMinutes = 420) {
  const day = scheduleDayWindow(value, startMinutes);
  const safeInterval = Math.max(15, Math.min(1440, Number(interval || 120)));
  const index = Math.floor((value.getTime() - day.startMs) / 60000 / safeInterval);
  const startMs = day.startMs + index * safeInterval * 60000;
  return { index, startMs, endMs: Math.min(day.endMs, startMs + safeInterval * 60000) };
}

function currentSessionIndex(value, interval, startMinutes = 420) {
  return sessionWindow(value, interval, startMinutes).index;
}""",
    "app schedule helpers",
)
write(p, t)

# Offline sync validates scans against the same schedule even after reconnect.
p = "worker/offline.js"
t = read(p)
t = t.replace(
    "COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes",
    "COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,\n            COALESCE(d.session_start_minutes, 420) AS session_start_minutes",
)
t = once(
    t,
    "SELECT id, name, session_interval_minutes, route_order_enforced",
    "SELECT id, name, session_interval_minutes, session_start_minutes, route_order_enforced",
    "offline bootstrap select",
)
t = once(
    t,
    "      sessionIntervalMinutes: Number(department.session_interval_minutes || 120),\n      routeOrderEnforced:",
    "      sessionIntervalMinutes: Number(department.session_interval_minutes || 120),\n      sessionStartMinutes: Number(department.session_start_minutes ?? 420),\n      routeOrderEnforced:",
    "offline bootstrap response",
)
t = once(
    t,
    "SELECT id, session_interval_minutes, route_order_enforced",
    "SELECT id, session_interval_minutes, session_start_minutes, route_order_enforced",
    "offline scan select",
)
t = once(
    t,
    """  const interval = Number(department.session_interval_minutes || 120);
  const day = malaysiaDayBounds(malaysiaDateKey(occurredAt));
  const sessionIndex = currentSessionIndex(occurredAt, interval);
  const startMs = day.startMs + sessionIndex * interval * 60000;
  const endMs = Math.min(day.endMs, startMs + interval * 60000);""",
    """  const interval = Number(department.session_interval_minutes || 120);
  const window = sessionWindow(occurredAt, interval, department.session_start_minutes);
  const sessionIndex = window.index;
  const startMs = window.startMs;
  const endMs = window.endMs;""",
    "offline scan window",
)
t = once(
    t,
    "    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),\n  };",
    "    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),\n    sessionStartMinutes: Number(user.session_start_minutes ?? 420),\n  };",
    "offline public user start",
)
t = once(
    t,
    """function currentSessionIndex(value, interval) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  return Math.floor(minuteOfDay / Math.max(15, Math.min(1440, Number(interval || 120))));
}""",
    """function scheduleDayWindow(value, startMinutes = 420) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  const safeStart = Math.max(0, Math.min(1439, Number(startMinutes ?? 420)));
  const localMidnightUtc = Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate());
  let startMs = localMidnightUtc - MALAYSIA_OFFSET_MS + safeStart * 60000;
  if (minuteOfDay < safeStart) startMs -= 86400000;
  return { startMs, endMs: startMs + 86400000 };
}

function sessionWindow(value, interval, startMinutes = 420) {
  const day = scheduleDayWindow(value, startMinutes);
  const safeInterval = Math.max(15, Math.min(1440, Number(interval || 120)));
  const index = Math.floor((value.getTime() - day.startMs) / 60000 / safeInterval);
  const startMs = day.startMs + index * safeInterval * 60000;
  return { index, startMs, endMs: Math.min(day.endMs, startMs + safeInterval * 60000) };
}

function currentSessionIndex(value, interval, startMinutes = 420) {
  return sessionWindow(value, interval, startMinutes).index;
}""",
    "offline schedule helpers",
)
write(p, t)

# Patrol screen: true schedule label + large persistent red end button.
p = "lib/features/patrol/patrol_screen.dart"
t = read(p)
t = t.replace(
    "_sessionIndex(DateTime.now(), bootstrap.sessionIntervalMinutes)",
    "_sessionIndex(DateTime.now(), bootstrap.sessionIntervalMinutes, bootstrap.sessionStartMinutes)",
)
t = t.replace(
    "      bootstrap.sessionIntervalMinutes,\n    );",
    "      bootstrap.sessionIntervalMinutes,\n      bootstrap.sessionStartMinutes,\n    );",
)
t = t.replace(
    "_dayKey(DateTime.now())",
    "_scheduleDayKey(DateTime.now(), bootstrap.sessionStartMinutes)",
)
t = once(
    t,
    """  int _sessionIndex(DateTime value, int interval) {
    final local = value.toLocal();
    final safeInterval = interval.clamp(15, 1440);
    return (local.hour * 60 + local.minute) ~/ safeInterval;
  }

  String _dayKey(DateTime value) {
    final local = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }""",
    """  _SessionWindow _sessionWindow(DateTime value, int interval, int startMinutes) {
    final local = value.toLocal();
    final safeInterval = interval.clamp(15, 1440);
    final safeStart = startMinutes.clamp(0, 1439);
    var anchor = DateTime(local.year, local.month, local.day)
        .add(Duration(minutes: safeStart));
    if (local.isBefore(anchor)) anchor = anchor.subtract(const Duration(days: 1));
    final index = local.difference(anchor).inMinutes ~/ safeInterval;
    final start = anchor.add(Duration(minutes: index * safeInterval));
    final dayEnd = anchor.add(const Duration(days: 1));
    final rawEnd = start.add(Duration(minutes: safeInterval));
    final end = rawEnd.isAfter(dayEnd) ? dayEnd : rawEnd;
    return _SessionWindow(index: index, start: start, end: end);
  }

  int _sessionIndex(DateTime value, int interval, int startMinutes) =>
      _sessionWindow(value, interval, startMinutes).index;

  String _scheduleDayKey(DateTime value, int startMinutes) {
    final local = value.toLocal();
    final safeStart = startMinutes.clamp(0, 1439);
    var anchor = DateTime(local.year, local.month, local.day)
        .add(Duration(minutes: safeStart));
    if (local.isBefore(anchor)) anchor = anchor.subtract(const Duration(days: 1));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${anchor.year}-${two(anchor.month)}-${two(anchor.day)}';
  }

  String _hm(DateTime value) {
    final local = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }""",
    "patrol schedule helpers",
)
t = once(
    t,
    "    final next = bootstrap == null ? null : _nextCheckpoint(bootstrap);\n    final sessionEvents = bootstrap == null",
    "    final next = bootstrap == null ? null : _nextCheckpoint(bootstrap);\n    final activeSession = bootstrap == null\n        ? null\n        : _sessionWindow(DateTime.now(), bootstrap.sessionIntervalMinutes, bootstrap.sessionStartMinutes);\n    final sessionLabel = activeSession == null\n        ? 'Sesi Rondaan belum tersedia'\n        : 'Sesi Rondaan ${activeSession.index + 1} • ${_hm(activeSession.start)} – ${_hm(activeSession.end)}';\n    final sessionEvents = bootstrap == null",
    "patrol active session label",
)
end_icon = """          IconButton(
            tooltip: 'Tamat rondaan',
            onPressed: _ending ? null : _finishPatrol,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
"""
if t.count(end_icon) != 1:
    raise RuntimeError(f"end icon expected once, got {t.count(end_icon)}")
t = t.replace(end_icon, "", 1)
t = once(
    t,
    "      ),\n      body: SafeArea(",
    """      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 66,
          child: FilledButton.icon(
            onPressed: _ending ? null : _finishPatrol,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC0392B),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF6F2A25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.stop_circle_rounded, size: 30),
            label: Text(
              _ending ? 'MENAMATKAN RONDAAN…' : 'TAMAT RONDAAN',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
      body: SafeArea(""",
    "large end button",
)
t = once(
    t,
    "                interval: bootstrap?.sessionIntervalMinutes ??\n                    widget.user.sessionIntervalMinutes,\n              ),",
    "                interval: bootstrap?.sessionIntervalMinutes ??\n                    widget.user.sessionIntervalMinutes,\n                sessionLabel: sessionLabel,\n              ),",
    "route card call label",
)
t = once(
    t,
    "    required this.interval,\n  });",
    "    required this.interval,\n    required this.sessionLabel,\n  });",
    "route card ctor label",
)
t = once(
    t,
    "  final int interval;\n\n  @override",
    "  final int interval;\n  final String sessionLabel;\n\n  @override",
    "route card field label",
)
t = once(
    t,
    "                        Text('Sesi setiap $interval minit'),",
    "                        Text(\n                          sessionLabel,\n                          style: const TextStyle(\n                            fontWeight: FontWeight.w900,\n                            color: Color(0xFFA29BFE),\n                          ),\n                        ),\n                        const SizedBox(height: 3),\n                        Text('Kadar: setiap $interval minit'),",
    "route card display label",
)
marker = "class _LiveHero extends StatelessWidget {"
window_class = """class _SessionWindow {
  const _SessionWindow({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;
  final DateTime start;
  final DateTime end;
}

"""
if marker not in t:
    raise RuntimeError("patrol window class marker missing")
t = t.replace(marker, window_class + marker, 1)
write(p, t)

# Dashboard session alarm follows the same department anchor.
p = "lib/features/dashboard/dashboard_screen.dart"
t = read(p)
t = once(
    t,
    "  late int _sessionIntervalMinutes;\n  Timer? _sessionTimer;",
    "  late int _sessionIntervalMinutes;\n  late int _sessionStartMinutes;\n  Timer? _sessionTimer;",
    "dashboard start field",
)
t = once(
    t,
    "    _sessionIntervalMinutes = widget.user.sessionIntervalMinutes;\n    _lastSessionKey = _sessionKey(DateTime.now());",
    "    _sessionIntervalMinutes = widget.user.sessionIntervalMinutes;\n    _sessionStartMinutes = widget.user.sessionStartMinutes;\n    _lastSessionKey = _sessionKey(DateTime.now());",
    "dashboard start init",
)
t = once(
    t,
    """      if (_sessionIntervalMinutes != bootstrap.sessionIntervalMinutes) {
        setState(() => _sessionIntervalMinutes = bootstrap.sessionIntervalMinutes);
        _lastSessionKey = _sessionKey(DateTime.now());
      }""",
    """      if (_sessionIntervalMinutes != bootstrap.sessionIntervalMinutes ||
          _sessionStartMinutes != bootstrap.sessionStartMinutes) {
        setState(() {
          _sessionIntervalMinutes = bootstrap.sessionIntervalMinutes;
          _sessionStartMinutes = bootstrap.sessionStartMinutes;
        });
        _lastSessionKey = _sessionKey(DateTime.now());
      }""",
    "dashboard refresh",
)
t = once(
    t,
    """      if (cached != null &&
          _sessionIntervalMinutes != cached.sessionIntervalMinutes &&
          mounted) {
        setState(() => _sessionIntervalMinutes = cached.sessionIntervalMinutes);
      }""",
    """      if (cached != null && mounted &&
          (_sessionIntervalMinutes != cached.sessionIntervalMinutes ||
              _sessionStartMinutes != cached.sessionStartMinutes)) {
        setState(() {
          _sessionIntervalMinutes = cached.sessionIntervalMinutes;
          _sessionStartMinutes = cached.sessionStartMinutes;
        });
      }""",
    "dashboard cached refresh",
)
t = once(
    t,
    """  String _sessionKey(DateTime value) {
    final local = value.toLocal();
    final interval = _sessionIntervalMinutes <= 0 ? 120 : _sessionIntervalMinutes;
    final index = (local.hour * 60 + local.minute) ~/ interval;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}-$index-$interval';
  }""",
    """  String _sessionKey(DateTime value) {
    final local = value.toLocal();
    final interval = _sessionIntervalMinutes.clamp(15, 1440);
    final startMinutes = _sessionStartMinutes.clamp(0, 1439);
    final minuteOfDay = local.hour * 60 + local.minute;
    final relativeMinutes = (minuteOfDay - startMinutes + 1440) % 1440;
    final index = relativeMinutes ~/ interval;
    final scheduleDay = minuteOfDay < startMinutes
        ? local.subtract(const Duration(days: 1))
        : local;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${scheduleDay.year}-${two(scheduleDay.month)}-${two(scheduleDay.day)}-$index-$interval-$startMinutes';
  }""",
    "dashboard session key",
)
write(p, t)

# Sanity checks before the workflow invokes node/flutter validation.
for path in [
    "lib/core/api/app_user.dart",
    "lib/core/offline/offline_models.dart",
    "lib/core/api/api_service.dart",
    "lib/features/admin/department_maintenance_screen.dart",
    "lib/features/patrol/patrol_screen.dart",
    "lib/features/dashboard/dashboard_screen.dart",
    "worker/index.js",
    "worker/app.js",
    "worker/offline.js",
]:
    data = read(path)
    if "sessionStartMinutes" not in data and "session_start_minutes" not in data:
        raise RuntimeError(f"session start wiring missing from {path}")

print("Patrol schedule upgrade applied in working tree.")
