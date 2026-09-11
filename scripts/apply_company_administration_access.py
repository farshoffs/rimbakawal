from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"Anchor not found for {label}")
    return text.replace(old, new, 1)


def replace_all(text: str, old: str, new: str, label: str, expected_min: int = 1) -> str:
    if new in text and old not in text:
        return text
    count = text.count(old)
    if count < expected_min:
        raise RuntimeError(f"Expected at least {expected_min} anchors for {label}, found {count}")
    return text.replace(old, new)


# ---------------------------------------------------------------------------
# Flutter role model
# ---------------------------------------------------------------------------
path = "lib/core/api/app_user.dart"
text = read(path)
text = replace_once(
    text,
    "  bool get isManagement => jawatan.toLowerCase() == 'management';\n  bool get isSupervisor => jawatan.toLowerCase() == 'supervisor';\n  bool get canMonitor => isManagement || isSupervisor;\n",
    "  bool get isManagement => jawatan.toLowerCase() == 'management';\n  bool get isAdministration => jawatan.toLowerCase() == 'administration';\n  bool get isSupervisor => jawatan.toLowerCase() == 'supervisor';\n  bool get canMonitor => isManagement || isSupervisor;\n  bool get canDownloadReports => isManagement || isAdministration;\n",
    "AppUser role getters",
)
text = replace_once(
    text,
    "    'management' => 'Pengurusan',\n    'supervisor' => 'Penyelia',\n    'patrol' => 'Pengawal Rondaan',\n",
    "    'management' => 'Admin Sistem',\n    'administration' => 'Pentadbiran Syarikat',\n    'supervisor' => 'Penyelia',\n    'patrol' => 'Pengawal Rondaan',\n",
    "role labels",
)
write(path, text)


# ---------------------------------------------------------------------------
# Dedicated report-only dashboard for company administration
# ---------------------------------------------------------------------------
report_only_screen = r'''import 'package:flutter/material.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import '../../core/nfc/nfc_service.dart';
import '../auth/login_screen.dart';
import 'report_screen.dart';

class ReportOnlyDashboardScreen extends StatelessWidget {
  const ReportOnlyDashboardScreen({
    required this.user,
    required this.api,
    required this.nfcService,
    required this.mockMode,
    super.key,
  });

  final AppUser user;
  final ApiService api;
  final NfcService nfcService;
  final bool mockMode;

  Future<void> _logout(BuildContext context) async {
    await api.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          nfcService: nfcService,
          mockMode: mockMode,
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZPatrol'),
        actions: [
          IconButton(
            tooltip: 'Log keluar',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Center(
              child: Image.asset(
                'assets/branding/zpatrol_icon.png',
                width: 96,
                height: 96,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              user.nama,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              '${user.jawatanPaparan} • ${user.jabatan}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, size: 42),
                    const SizedBox(height: 14),
                    Text(
                      'Laporan PDF',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Akaun Pentadbiran Syarikat dikhaskan untuk menjana dan memuat turun laporan PDF bagi lokasi sendiri.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReportScreen(api: api),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Buka Laporan PDF'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline_rounded),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Akses rondaan, kehadiran, pemantauan, pengurusan pengguna, tetapan checkpoint dan fungsi pentadbiran sistem tidak diberikan kepada tahap ini.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
'''
write("lib/features/admin/report_only_dashboard_screen.dart", report_only_screen)


# Route Administration accounts directly to report-only UI.
path = "lib/main.dart"
text = read(path)
text = replace_once(
    text,
    "import 'features/auth/login_screen.dart';\n",
    "import 'features/admin/report_only_dashboard_screen.dart';\nimport 'features/auth/login_screen.dart';\n",
    "main report-only import",
)
text = replace_once(
    text,
    "        return NotificationAlertGate(\n          user: user,\n",
    "        if (user.isAdministration) {\n          return ReportOnlyDashboardScreen(\n            user: user,\n            api: _api,\n            nfcService: _nfcService,\n            mockMode: useMockNfc,\n          );\n        }\n\n        return NotificationAlertGate(\n          user: user,\n",
    "main Administration route",
)
write(path, text)


# ---------------------------------------------------------------------------
# API client: block / unblock user
# ---------------------------------------------------------------------------
path = "lib/core/api/api_service.dart"
text = read(path)
insert_anchor = "  Future<AppUser> updateAdminUser({\n"
method = r'''  Future<AppUser> setAdminUserBlocked({
    required int userId,
    required bool blocked,
  }) async {
    final data = _decode(
      await http.put(
        _uri('/api/admin/users/$userId/status'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'blocked': blocked}),
      ),
    );
    return AppUser.fromJson(
      Map<String, dynamic>.from(data['user'] as Map),
    );
  }

'''
if method not in text:
    if insert_anchor not in text:
        raise RuntimeError("Anchor not found for API block method")
    text = text.replace(insert_anchor, method + insert_anchor, 1)
write(path, text)


# ---------------------------------------------------------------------------
# System-admin user maintenance UI
# ---------------------------------------------------------------------------
path = "lib/features/admin/user_maintenance_screen.dart"
text = read(path)
text = text.replace("title: const Text('Senarai PK'),", "title: const Text('Pengguna Syarikat'),")
text = text.replace("'${filteredUsers.length} PK'", "'${filteredUsers.length} pengguna'")
text = text.replace("const Center(child: Text('Tiada PK untuk Sekolah ini.'))", "const Center(child: Text('Tiada pengguna untuk Sekolah ini.'))")
text = text.replace("label: const Text('Tambah PK'),", "label: const Text('Tambah Pengguna'),")
text = replace_once(
    text,
    "                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n${user.jawatanPaparan} • ${user.guardStatus} • ${user.jabatan}',\n",
    "                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n${user.jawatanPaparan} • ${user.guardStatus} • ${user.jabatan}\\nStatus Akaun: ${user.active ? 'AKTIF' : 'DISEKAT'}',\n",
    "user account status label",
)
text = replace_once(
    text,
    "                              trailing: const Icon(Icons.edit_rounded),\n",
    "                              trailing: Icon(\n                                user.active\n                                    ? Icons.edit_rounded\n                                    : Icons.block_rounded,\n                                color: user.active\n                                    ? null\n                                    : Theme.of(context).colorScheme.error,\n                              ),\n",
    "blocked trailing icon",
)

role_items_old = r'''                items: const [
                  DropdownMenuItem(
                    value: 'Patrol',
                    child: Text('Pengawal Rondaan'),
                  ),
                  DropdownMenuItem(
                    value: 'Supervisor',
                    child: Text('Penyelia'),
                  ),
                  DropdownMenuItem(
                    value: 'Management',
                    child: Text('Pengurusan'),
                  ),
                ],
'''
role_items_new = r'''                items: const [
                  DropdownMenuItem(
                    value: 'Patrol',
                    child: Text('Pengawal Rondaan'),
                  ),
                  DropdownMenuItem(
                    value: 'Supervisor',
                    child: Text('Penyelia'),
                  ),
                  DropdownMenuItem(
                    value: 'Administration',
                    child: Text('Pentadbiran Syarikat'),
                  ),
                ],
'''
text = replace_all(text, role_items_old, role_items_new, "company role dropdowns", expected_min=2)

save_anchor = "  Future<void> _save() async {\n"
toggle_method = r'''  Future<void> _toggleBlocked() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.setAdminUserBlocked(
        userId: widget.user.id,
        blocked: widget.user.active,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

'''
# Insert only in _EditUserDialogState: first _save occurrence is its _save.
if toggle_method not in text:
    if save_anchor not in text:
        raise RuntimeError("Anchor not found for block toggle UI")
    text = text.replace(save_anchor, toggle_method + save_anchor, 1)

button_anchor = r'''              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
              ),

              const SizedBox(height: 8),
'''
button_new = r'''              OutlinedButton.icon(
                onPressed: _saving ? null : _toggleBlocked,
                icon: Icon(
                  widget.user.active
                      ? Icons.block_rounded
                      : Icons.lock_open_rounded,
                ),
                label: Text(
                  widget.user.active ? 'Sekat Akaun' : 'Nyahsekat Akaun',
                ),
                style: widget.user.active
                    ? OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
              ),

              const SizedBox(height: 8),
'''
text = replace_once(text, button_anchor, button_new, "block account button")
write(path, text)

path = "lib/features/admin/admin_screen.dart"
text = read(path)
text = text.replace("title: 'Senarai PK',", "title: 'Pengguna Syarikat',")
text = text.replace("subtitle: 'Tambah PK dan tetapkan Sekolah.',", "subtitle: 'Tambah pengguna, tetapkan peranan dan urus status akaun.',")
write(path, text)


# ---------------------------------------------------------------------------
# Worker entry gate: Administration is server-side report-only.
# ---------------------------------------------------------------------------
path = "worker/reports.js"
text = read(path)
text = replace_once(
    text,
    "import commandCenterWorker from './command_center_period.js';\n\n",
    "import commandCenterWorker from './command_center_period.js';\n\nconst SESSION_COOKIE = 'rk_session';\n\n",
    "reports session cookie",
)
text = replace_once(
    text,
    "    const url = new URL(request.url);\n    if (url.pathname === '/api/admin/reports' && request.method === 'GET') {\n",
    "    const url = new URL(request.url);\n    const reportOnlyAllowed =\n      (url.pathname === '/api/auth/session' && request.method === 'GET') ||\n      (url.pathname === '/api/auth/logout' && request.method === 'POST') ||\n      (url.pathname === '/api/admin/reports' && request.method === 'GET') ||\n      (url.pathname === '/api/admin/departments' && request.method === 'GET');\n    if (url.pathname.startsWith('/api/') &&\n        url.pathname !== '/api/auth/login' &&\n        !reportOnlyAllowed) {\n      const denied = await denyAdministrationOperationalAccess(request, env);\n      if (denied) return denied;\n    }\n    if (url.pathname === '/api/admin/reports' && request.method === 'GET') {\n",
    "reports central role gate",
)
text = replace_once(
    text,
    "  const rawDepartmentId = url.searchParams.get('departmentId');\n  const departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);\n",
    "  const rawDepartmentId = url.searchParams.get('departmentId');\n  const downstreamDepartmentId = payload.department?.id == null\n    ? null\n    : Number(payload.department.id);\n  const departmentId = rawDepartmentId == null\n    ? downstreamDepartmentId\n    : Number(rawDepartmentId);\n",
    "reports effective department scope",
)
helpers = r'''
async function denyAdministrationOperationalAccess(request, env) {
  const token = getSessionToken(request);
  if (!token) return null;
  const user = await env.DB.prepare(
    `SELECT u.jawatan
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
     LIMIT 1`,
  ).bind(await sha256(token), Date.now()).first();
  if (String(user?.jawatan || '').trim().toLowerCase() !== 'administration') {
    return null;
  }
  return json({
    error: 'Akaun Pentadbiran Syarikat hanya dibenarkan mengakses dan memuat turun laporan PDF.',
  }, 403);
}

function getSessionToken(request) {
  const authorization = request.headers.get('Authorization') ?? '';
  if (authorization.startsWith('Bearer ')) return authorization.slice(7).trim();
  const cookie = request.headers.get('Cookie') ?? '';
  for (const part of cookie.split(';')) {
    const [name, ...value] = part.trim().split('=');
    if (name === SESSION_COOKIE) {
      try {
        return decodeURIComponent(value.join('='));
      } catch (_) {
        return value.join('=');
      }
    }
  }
  return null;
}

async function sha256(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

'''
json_anchor = "function json(data, status = 200) {\n"
if helpers not in text:
    if json_anchor not in text:
        raise RuntimeError("Anchor not found for reports auth helpers")
    text = text.replace(json_anchor, helpers + json_anchor, 1)
write(path, text)


# ---------------------------------------------------------------------------
# Worker report authorization + new role creation
# ---------------------------------------------------------------------------
path = "worker/app.js"
text = read(path)
text = text.replace(
    "if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan mesti Patrol, Supervisor atau Management.' }, 400);\n  }",
    "if (!['Patrol', 'Supervisor', 'Administration', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan mesti Patrol, Supervisor, Administration atau Management.' }, 400);\n  }",
)
text = replace_once(
    text,
    "async function adminReport(request, env, url) {\n  const auth = await requireManagement(request, env);\n  if (auth.response) return auth.response;\n\n  const today = malaysiaDateKey(new Date());\n  const from = url.searchParams.get('from') || today;\n  const to = url.searchParams.get('to') || today;\n  const rawDepartmentId = url.searchParams.get('departmentId');\n  const departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);\n",
    "async function adminReport(request, env, url) {\n  const auth = await requireReportAccess(request, env);\n  if (auth.response) return auth.response;\n\n  const today = malaysiaDateKey(new Date());\n  const from = url.searchParams.get('from') || today;\n  const to = url.searchParams.get('to') || today;\n  const role = String(auth.user.jawatan || '').trim().toLowerCase();\n  const ownDepartmentId = Number(auth.user.department_id || 0) || null;\n  const rawDepartmentId = url.searchParams.get('departmentId');\n  let departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);\n  if (role === 'administration') {\n    if (!ownDepartmentId) {\n      return json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Sekolah.' }, 409);\n    }\n    if (departmentId != null && departmentId !== ownDepartmentId) {\n      return json({ error: 'Pentadbiran Syarikat hanya boleh memuat turun laporan lokasi sendiri.' }, 403);\n    }\n    departmentId = ownDepartmentId;\n  }\n",
    "app report role scope",
)
helper_anchor = "async function requireManagement(request, env) {\n"
report_helper = r'''async function requireReportAccess(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  if (role !== 'management' && role !== 'administration') {
    return {
      response: json({
        error: 'Akses laporan hanya untuk Admin Sistem atau Pentadbiran Syarikat.',
      }, 403),
    };
  }
  return auth;
}

'''
if report_helper not in text:
    if helper_anchor not in text:
        raise RuntimeError("Anchor not found for app report helper")
    text = text.replace(helper_anchor, report_helper + helper_anchor, 1)
write(path, text)


# ---------------------------------------------------------------------------
# Worker user-management endpoint: only Management can block/unblock.
# ---------------------------------------------------------------------------
path = "worker/index.js"
text = read(path)
route_anchor = r'''      match = url.pathname.match(/^\/api\/admin\/users\/(\d+)$/);
      if (match && request.method === 'PUT') {
        return updateAdminUser(request, env, Number(match[1]));
      }

'''
route_new = route_anchor + r'''      match = url.pathname.match(/^\/api\/admin\/users\/(\d+)\/status$/);
      if (match && request.method === 'PUT') {
        return updateAdminUserStatus(request, env, Number(match[1]));
      }

'''
text = replace_once(text, route_anchor, route_new, "block account route")
text = text.replace(
    "if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan pengguna tidak sah.' }, 400);\n  }",
    "if (!['Patrol', 'Supervisor', 'Administration', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan pengguna tidak sah.' }, 400);\n  }",
)
status_anchor = "async function updateUserDepartment(request, env, userId) {\n"
status_function = r'''async function updateAdminUserStatus(request, env, userId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  if (!Number.isInteger(userId) || userId <= 0) {
    return json({ error: 'Pengguna tidak sah.' }, 400);
  }

  const body = await readJson(request);
  if (typeof body.blocked !== 'boolean') {
    return json({ error: 'Status sekatan akaun tidak sah.' }, 400);
  }
  if (Number(auth.user.id) === userId && body.blocked === true) {
    return json({ error: 'Admin Sistem tidak boleh menyekat akaun sendiri.' }, 409);
  }

  const existing = await getUserById(env, userId);
  if (!existing) return json({ error: 'Pengguna tidak ditemui.' }, 404);

  await env.DB.prepare('UPDATE users SET active = ? WHERE id = ?')
    .bind(body.blocked ? 0 : 1, userId)
    .run();
  if (body.blocked) {
    await env.DB.prepare('DELETE FROM sessions WHERE user_id = ?').bind(userId).run();
  }

  const updated = await getUserById(env, userId);
  return json({
    user: publicUser(updated),
    blocked: body.blocked,
  });
}

'''
if status_function not in text:
    if status_anchor not in text:
        raise RuntimeError("Anchor not found for block status function")
    text = text.replace(status_anchor, status_function + status_anchor, 1)

# Keep the base implementation compatible if this route is ever reached directly.
old_dept = r'''async function adminDepartments(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const result = await env.DB.prepare(
    `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN checkpoints c ON c.department_id = d.id
     WHERE d.active = 1
     GROUP BY d.id
     ORDER BY d.name ASC`,
  ).all();
  return json({ departments: (result.results ?? []).map(departmentJson) });
}
'''
new_dept = r'''async function adminDepartments(request, env) {
  const auth = await requireReportAccess(request, env);
  if (auth.response) return auth.response;
  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const scopeDepartment = role === 'administration'
    ? Number(auth.user.department_id || 0) || null
    : null;
  if (role === 'administration' && !scopeDepartment) {
    return json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Sekolah.' }, 409);
  }

  const sql = `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN checkpoints c ON c.department_id = d.id
     WHERE d.active = 1 ${scopeDepartment ? 'AND d.id = ?' : ''}
     GROUP BY d.id
     ORDER BY d.name ASC`;
  const result = scopeDepartment
    ? await env.DB.prepare(sql).bind(scopeDepartment).all()
    : await env.DB.prepare(sql).all();
  return json({ departments: (result.results ?? []).map(departmentJson) });
}
'''
text = replace_once(text, old_dept, new_dept, "base report department scope")
require_anchor = "async function requireManagement(request, env) {\n"
require_report = r'''async function requireReportAccess(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  if (role !== 'management' && role !== 'administration') {
    return {
      response: json({
        error: 'Akses laporan hanya untuk Admin Sistem atau Pentadbiran Syarikat.',
      }, 403),
    };
  }
  return auth;
}

'''
if require_report not in text:
    if require_anchor not in text:
        raise RuntimeError("Anchor not found for index report helper")
    text = text.replace(require_anchor, require_report + require_anchor, 1)
write(path, text)


# ---------------------------------------------------------------------------
# Live /api/admin/departments implementation is in attendance.js.
# ---------------------------------------------------------------------------
path = "worker/attendance.js"
text = read(path)
old_attendance_dept = r'''async function adminDepartments(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const result = await env.DB.prepare(
    `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            d.attendance_latitude, d.attendance_longitude, d.attendance_radius_m,
            d.attendance_location_label, d.company_name, d.zone,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN checkpoints c ON c.department_id = d.id
     WHERE d.active = 1
     GROUP BY d.id
     ORDER BY d.name ASC`,
  ).all();
  return json({ departments: (result.results ?? []).map(departmentJson) });
}
'''
new_attendance_dept = r'''async function adminDepartments(request, env) {
  const auth = await requireReportAccess(request, env);
  if (auth.response) return auth.response;
  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const scopeDepartment = role === 'administration'
    ? Number(auth.user.department_id || 0) || null
    : null;
  if (role === 'administration' && !scopeDepartment) {
    return json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Sekolah.' }, 409);
  }

  const sql = `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            d.attendance_latitude, d.attendance_longitude, d.attendance_radius_m,
            d.attendance_location_label, d.company_name, d.zone,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN checkpoints c ON c.department_id = d.id
     WHERE d.active = 1 ${scopeDepartment ? 'AND d.id = ?' : ''}
     GROUP BY d.id
     ORDER BY d.name ASC`;
  const result = scopeDepartment
    ? await env.DB.prepare(sql).bind(scopeDepartment).all()
    : await env.DB.prepare(sql).all();
  return json({ departments: (result.results ?? []).map(departmentJson) });
}
'''
text = replace_once(text, old_attendance_dept, new_attendance_dept, "attendance report department scope")
require_anchor = "async function requireManagement(request, env) {\n"
if require_report not in text:
    if require_anchor not in text:
        raise RuntimeError("Anchor not found for attendance report helper")
    text = text.replace(require_anchor, require_report + require_anchor, 1)
write(path, text)


# ---------------------------------------------------------------------------
# Access-control documentation kept with the codebase.
# ---------------------------------------------------------------------------
doc = r'''# ZPatrol - Matriks Akses Pengguna

## Peranan

| Peranan | Kod | Skop |
| --- | --- | --- |
| Admin Sistem | `Management` | Pentadbiran penuh sistem merentas lokasi. |
| Pentadbiran Syarikat | `Administration` | Laporan PDF sahaja untuk lokasi sendiri. |
| Penyelia | `Supervisor` | Operasi rondaan dan pemantauan lokasi sendiri. |
| Pengawal Rondaan | `Patrol` | Operasi rondaan harian. |

## Akses utama

- **Admin Sistem**: semua fungsi, konfigurasi lokasi/checkpoint, pengguna, pemantauan, kehadiran, SOS/insiden, laporan PDF, dan sekat/nyahsekat akaun pengguna.
- **Pentadbiran Syarikat**: hanya skrin laporan PDF dan muat turun PKK 2, PKK 3, PKK 4 bagi lokasi yang dipautkan. Endpoint operasi disekat pada server.
- **Penyelia**: Mula Rondaan, Kehadiran, Sejarah, Profil dan Pemantauan operasi lokasi sendiri. Tiada konfigurasi Admin Sistem dan tiada pengurusan akaun.
- **Pengawal Rondaan**: Mula Rondaan, Kehadiran, Sejarah dan Profil. Tiada Pemantauan atau Pentadbiran.

## Sekatan akaun

Hanya `Management` boleh memanggil `PUT /api/admin/users/:id/status`. Menyekat pengguna menetapkan `active = 0` dan membatalkan semua sesi pengguna tersebut. Pengguna yang disekat tidak boleh log masuk atau menggunakan sesi sedia ada.
'''
write("docs/ZPATROL_ACCESS_CONTROL.md", doc)

print("ZPatrol company administration and account-blocking patch applied.")
