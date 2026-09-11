from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def write(path, text):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8')


def once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f'Anchor not found: {label}')
    return text.replace(old, new, 1)


def all_(text, old, new, label, minimum=1):
    if old not in text:
        if new in text:
            return text
        raise RuntimeError(f'Anchor not found: {label}')
    if text.count(old) < minimum:
        raise RuntimeError(f'Not enough anchors for {label}')
    return text.replace(old, new)


# 1. Role model.
p = 'lib/core/api/app_user.dart'
t = read(p)
t = once(t,
"  bool get isManagement => jawatan.toLowerCase() == 'management';\n  bool get isSupervisor => jawatan.toLowerCase() == 'supervisor';\n  bool get canMonitor => isManagement || isSupervisor;\n",
"  bool get isManagement => jawatan.toLowerCase() == 'management';\n  bool get isAdministration => jawatan.toLowerCase() == 'administration';\n  bool get isSupervisor => jawatan.toLowerCase() == 'supervisor';\n  bool get canMonitor => isManagement || isSupervisor;\n  bool get canDownloadReports => isManagement || isAdministration;\n",
'AppUser role getters')
t = once(t,
"    'management' => 'Pengurusan',\n    'supervisor' => 'Penyelia',\n    'patrol' => 'Pengawal Rondaan',\n",
"    'management' => 'Admin Sistem',\n    'administration' => 'Pentadbiran Syarikat',\n    'supervisor' => 'Penyelia',\n    'patrol' => 'Pengawal Rondaan',\n",
'role labels')
write(p, t)

# 2. Report-only dashboard.
write('lib/features/admin/report_only_dashboard_screen.dart', '''import 'package:flutter/material.dart';

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
''')

# 3. Route Administration accounts directly to report-only dashboard.
p = 'lib/main.dart'
t = read(p)
t = once(t, "import 'features/auth/login_screen.dart';\n",
         "import 'features/admin/report_only_dashboard_screen.dart';\nimport 'features/auth/login_screen.dart';\n", 'main import')
t = once(t,
"        return NotificationAlertGate(\n          user: user,\n",
"        if (user.isAdministration) {\n          return ReportOnlyDashboardScreen(\n            user: user,\n            api: _api,\n            nfcService: _nfcService,\n            mockMode: useMockNfc,\n          );\n        }\n\n        return NotificationAlertGate(\n          user: user,\n", 'main role route')
write(p, t)

# 4. Client block/unblock API.
p = 'lib/core/api/api_service.dart'
t = read(p)
method = '''  Future<AppUser> setAdminUserBlocked({
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
if method not in t:
    anchor = '  Future<AppUser> updateAdminUser({\n'
    if anchor not in t:
        raise RuntimeError('Anchor not found: api updateAdminUser')
    t = t.replace(anchor, method + anchor, 1)
write(p, t)

# 5. Report screen auto-selects the only allowed department.
p = 'lib/features/admin/report_screen.dart'
t = read(p)
t = once(t,
"      setState(() {\n        _departments = departments.where((item) => item.active).toList();\n        _loadingDepartments = false;\n      });\n",
"      setState(() {\n        _departments = departments.where((item) => item.active).toList();\n        if (_departments.length == 1) {\n          _departmentId = _departments.first.id;\n        }\n        _loadingDepartments = false;\n      });\n", 'report auto department')
write(p, t)

# 6. User maintenance UI.
p = 'lib/features/admin/user_maintenance_screen.dart'
t = read(p)
t = t.replace("title: const Text('Senarai PK'),", "title: const Text('Pengguna Syarikat'),")
t = t.replace("'${filteredUsers.length} PK'", "'${filteredUsers.length} pengguna'")
t = t.replace("const Center(child: Text('Tiada PK untuk Sekolah ini.'))", "const Center(child: Text('Tiada pengguna untuk Sekolah ini.'))")
t = t.replace("label: const Text('Tambah PK'),", "label: const Text('Tambah Pengguna'),")
t = once(t,
"                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n${user.jawatanPaparan} • ${user.guardStatus} • ${user.jabatan}',\n",
"                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n${user.jawatanPaparan} • ${user.guardStatus} • ${user.jabatan}\\nStatus Akaun: ${user.active ? 'AKTIF' : 'DISEKAT'}',\n", 'account status subtitle')
t = once(t, "                              trailing: const Icon(Icons.edit_rounded),\n",
"                              trailing: Icon(\n                                user.active\n                                    ? Icons.edit_rounded\n                                    : Icons.block_rounded,\n                                color: user.active\n                                    ? null\n                                    : Theme.of(context).colorScheme.error,\n                              ),\n", 'blocked icon')
roles_old = '''                items: const [
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
roles_new = '''                items: const [
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
t = all_(t, roles_old, roles_new, 'role dropdowns', minimum=2)
toggle = '''  Future<void> _toggleBlocked() async {
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
if toggle not in t:
    marker = '  Future<void> _save() async {\n'
    idx = t.find(marker, t.find('class _EditUserDialogState'))
    if idx < 0:
        raise RuntimeError('Anchor not found: edit save')
    t = t[:idx] + toggle + t[idx:]
button_old = '''              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
              ),

              const SizedBox(height: 8),
'''
button_new = '''              OutlinedButton.icon(
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
t = once(t, button_old, button_new, 'block button')
write(p, t)

p = 'lib/features/admin/admin_screen.dart'
t = read(p).replace("title: 'Senarai PK',", "title: 'Pengguna Syarikat',")
t = t.replace("subtitle: 'Tambah PK dan tetapkan Sekolah.',", "subtitle: 'Tambah pengguna, tetapkan peranan dan urus status akaun.',")
write(p, t)

# 7. Central server-side report-only gate and report enrichment scope.
p = 'worker/reports.js'
t = read(p)
t = once(t, "import commandCenterWorker from './command_center_period.js';\n\n",
         "import commandCenterWorker from './command_center_period.js';\n\nconst SESSION_COOKIE = 'rk_session';\n\n", 'reports cookie')
t = once(t,
"    const url = new URL(request.url);\n    if (url.pathname === '/api/admin/reports' && request.method === 'GET') {\n",
"    const url = new URL(request.url);\n    const reportOnlyAllowed =\n      (url.pathname === '/api/auth/session' && request.method === 'GET') ||\n      (url.pathname === '/api/auth/logout' && request.method === 'POST') ||\n      (url.pathname === '/api/admin/reports' && request.method === 'GET') ||\n      (url.pathname === '/api/admin/departments' && request.method === 'GET');\n    if (url.pathname.startsWith('/api/') &&\n        url.pathname !== '/api/auth/login' &&\n        !reportOnlyAllowed) {\n      const denied = await denyAdministrationOperationalAccess(request, env);\n      if (denied) return denied;\n    }\n    if (url.pathname === '/api/admin/reports' && request.method === 'GET') {\n", 'reports gate')
t = once(t,
"  const rawDepartmentId = url.searchParams.get('departmentId');\n  const departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);\n",
"  const rawDepartmentId = url.searchParams.get('departmentId');\n  const downstreamDepartmentId = payload.department?.id == null\n    ? null\n    : Number(payload.department.id);\n  const departmentId = rawDepartmentId == null\n    ? downstreamDepartmentId\n    : Number(rawDepartmentId);\n", 'report effective department')
helpers = '''async function denyAdministrationOperationalAccess(request, env) {
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
      try { return decodeURIComponent(value.join('=')); } catch (_) { return value.join('='); }
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
if helpers not in t:
    marker = 'function json(data, status = 200) {\n'
    if marker not in t:
        raise RuntimeError('Anchor not found: reports json')
    t = t.replace(marker, helpers + marker, 1)
write(p, t)

# 8. App worker accepts new role and scopes reports.
p = 'worker/app.js'
t = read(p)
t = t.replace("if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan mesti Patrol, Supervisor atau Management.' }, 400);\n  }",
              "if (!['Patrol', 'Supervisor', 'Administration', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan mesti Patrol, Supervisor, Administration atau Management.' }, 400);\n  }")
t = once(t,
"async function adminReport(request, env, url) {\n  const auth = await requireManagement(request, env);\n  if (auth.response) return auth.response;\n\n  const today = malaysiaDateKey(new Date());\n  const from = url.searchParams.get('from') || today;\n  const to = url.searchParams.get('to') || today;\n  const rawDepartmentId = url.searchParams.get('departmentId');\n  const departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);\n",
"async function adminReport(request, env, url) {\n  const auth = await requireReportAccess(request, env);\n  if (auth.response) return auth.response;\n\n  const today = malaysiaDateKey(new Date());\n  const from = url.searchParams.get('from') || today;\n  const to = url.searchParams.get('to') || today;\n  const role = String(auth.user.jawatan || '').trim().toLowerCase();\n  const ownDepartmentId = Number(auth.user.department_id || 0) || null;\n  const rawDepartmentId = url.searchParams.get('departmentId');\n  let departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);\n  if (role === 'administration') {\n    if (!ownDepartmentId) {\n      return json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Sekolah.' }, 409);\n    }\n    if (departmentId != null && departmentId !== ownDepartmentId) {\n      return json({ error: 'Pentadbiran Syarikat hanya boleh memuat turun laporan lokasi sendiri.' }, 403);\n    }\n    departmentId = ownDepartmentId;\n  }\n", 'app report scope')
report_access = '''async function requireReportAccess(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth;
  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  if (role !== 'management' && role !== 'administration') {
    return { response: json({ error: 'Akses laporan hanya untuk Admin Sistem atau Pentadbiran Syarikat.' }, 403) };
  }
  return auth;
}

'''
if report_access not in t:
    marker = 'async function requireManagement(request, env) {\n'
    if marker not in t:
        raise RuntimeError('Anchor not found: app requireManagement')
    t = t.replace(marker, report_access + marker, 1)
write(p, t)

# 9. Base worker: role validation + Management-only block endpoint.
p = 'worker/index.js'
t = read(p)
route = '''      match = url.pathname.match(/^\\/api\\/admin\\/users\\/(\\d+)$/);
      if (match && request.method === 'PUT') {
        return updateAdminUser(request, env, Number(match[1]));
      }

'''
route2 = route + '''      match = url.pathname.match(/^\\/api\\/admin\\/users\\/(\\d+)\\/status$/);
      if (match && request.method === 'PUT') {
        return updateAdminUserStatus(request, env, Number(match[1]));
      }

'''
t = once(t, route, route2, 'block route')
t = t.replace("if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan pengguna tidak sah.' }, 400);\n  }",
              "if (!['Patrol', 'Supervisor', 'Administration', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan pengguna tidak sah.' }, 400);\n  }")
status_fn = '''async function updateAdminUserStatus(request, env, userId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  if (!Number.isInteger(userId) || userId <= 0) {
    return json({ error: 'Pengguna tidak sah.' }, 400);
  }
  const body = await readJson(request);
  if (typeof body.blocked !== 'boolean') {
    return json({ error: 'Status sekatan akaun tidak sah.' }, 400);
  }
  if (Number(auth.user.id) === userId && body.blocked) {
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
  return json({ user: publicUser(updated), blocked: body.blocked });
}

'''
if status_fn not in t:
    marker = 'async function updateUserDepartment(request, env, userId) {\n'
    if marker not in t:
        raise RuntimeError('Anchor not found: updateUserDepartment')
    t = t.replace(marker, status_fn + marker, 1)
write(p, t)

# 10. Live department list permits Administration, but only its own location.
p = 'worker/attendance.js'
t = read(p)
old = '''async function adminDepartments(request, env) {
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
new = '''async function adminDepartments(request, env) {
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
t = once(t, old, new, 'attendance departments')
if report_access not in t:
    marker = 'async function requireManagement(request, env) {\n'
    if marker not in t:
        raise RuntimeError('Anchor not found: attendance requireManagement')
    t = t.replace(marker, report_access + marker, 1)
write(p, t)

# 11. Access-control documentation.
write('docs/ZPATROL_ACCESS_CONTROL.md', '''# ZPatrol - Matriks Akses Pengguna

| Peranan | Kod | Skop |
| --- | --- | --- |
| Admin Sistem | `Management` | Pentadbiran penuh sistem merentas lokasi. |
| Pentadbiran Syarikat | `Administration` | Laporan PDF sahaja untuk lokasi sendiri. |
| Penyelia | `Supervisor` | Operasi rondaan dan pemantauan lokasi sendiri. |
| Pengawal Rondaan | `Patrol` | Operasi rondaan harian. |

## Akses utama

- **Admin Sistem**: semua fungsi, konfigurasi lokasi/checkpoint, pengguna, pemantauan, kehadiran, SOS/insiden, laporan PDF, dan sekat/nyahsekat akaun pengguna.
- **Pentadbiran Syarikat**: hanya laporan PDF PKK 2, PKK 3 dan PKK 4 bagi lokasi yang dipautkan. Endpoint operasi disekat di server.
- **Penyelia**: Mula Rondaan, Kehadiran, Sejarah, Profil dan Pusat Pemantauan lokasi sendiri. Tiada konfigurasi Admin Sistem dan tiada laporan PDF pentadbiran.
- **Pengawal Rondaan**: Mula Rondaan, Kehadiran, Sejarah dan Profil. Tiada Pemantauan, Pentadbiran atau laporan PDF pentadbiran.

## Sekatan akaun

Hanya `Management` boleh memanggil `PUT /api/admin/users/:id/status`. Menyekat akaun menetapkan `active = 0` dan memadam semua sesi aktif pengguna tersebut. Login dan semua sesi sedia ada akan ditolak sehingga Admin Sistem menyahsekat akaun.
''')

print('ZPatrol Administration access + blocking patch v2 applied successfully.')
