from pathlib import Path
import re

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


def replace_js_function(text: str, signature: str, replacement: str, label: str) -> str:
    start = text.find(signature)
    if start < 0:
        raise RuntimeError(f"Function not found for {label}: {signature}")
    search_from = start + len(signature)
    candidates = []
    for marker in ("\nasync function ", "\nfunction "):
        pos = text.find(marker, search_from)
        if pos >= 0:
            candidates.append(pos)
    end = min(candidates) if candidates else len(text)
    return text[:start] + replacement.rstrip() + "\n\n" + text[end + 1:]


# ---------------------------------------------------------------------------
# D1 company hierarchy: one company -> many schools, users inherit company.
# ---------------------------------------------------------------------------
migration = """CREATE TABLE IF NOT EXISTS companies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE departments ADD COLUMN company_id INTEGER REFERENCES companies(id);
ALTER TABLE users ADD COLUMN company_id INTEGER REFERENCES companies(id);

INSERT OR IGNORE INTO companies (name, active)
SELECT DISTINCT TRIM(company_name), 1
FROM departments
WHERE company_name IS NOT NULL AND TRIM(company_name) <> '';

UPDATE departments
SET company_id = (
  SELECT c.id
  FROM companies c
  WHERE LOWER(c.name) = LOWER(TRIM(departments.company_name))
  LIMIT 1
)
WHERE company_id IS NULL
  AND company_name IS NOT NULL
  AND TRIM(company_name) <> '';

UPDATE users
SET company_id = (
  SELECT d.company_id FROM departments d WHERE d.id = users.department_id
)
WHERE company_id IS NULL AND department_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_departments_company_id ON departments(company_id);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON users(company_id);
"""
write("migrations/0017_company_hierarchy.sql", migration)


# ---------------------------------------------------------------------------
# Flutter user model exposes company scope.
# ---------------------------------------------------------------------------
app_user = """class AppUser {
  const AppUser({
    required this.id,
    required this.nama,
    required this.noKadPengenalan,
    required this.jawatan,
    required this.jabatan,
    required this.profilePicture,
    required this.departmentId,
    required this.sessionIntervalMinutes,
    this.sessionStartMinutes = 420,
    this.noPk = '',
    this.guardStatus = 'Tetap',
    this.active = true,
    this.companyId,
    this.companyName = '',
  });

  final int id;
  final String nama;
  final String noKadPengenalan;
  final String jawatan;
  final String jabatan;
  final String? profilePicture;
  final int? departmentId;
  final int? companyId;
  final String companyName;
  final int sessionIntervalMinutes;
  final int sessionStartMinutes;
  final String noPk;
  final String guardStatus;
  final bool active;

  bool get isManagement => jawatan.toLowerCase() == 'management';
  bool get isAdministration => jawatan.toLowerCase() == 'administration';
  bool get isSupervisor => jawatan.toLowerCase() == 'supervisor';
  bool get canMonitor => isManagement || isSupervisor;
  bool get canDownloadReports => isManagement || isAdministration;
  String get jawatanPaparan => labelJawatan(jawatan);

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] as num).toInt(),
      nama: json['nama'] as String,
      noKadPengenalan: json['noKadPengenalan'] as String,
      jawatan: json['jawatan'] as String,
      jabatan: json['jabatan'] as String? ?? 'Belum ditetapkan',
      profilePicture: json['profilePicture'] as String?,
      departmentId: (json['departmentId'] as num?)?.toInt(),
      companyId: (json['companyId'] as num?)?.toInt(),
      companyName: json['companyName'] as String? ?? '',
      sessionIntervalMinutes:
          (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,
      sessionStartMinutes:
          (json['sessionStartMinutes'] as num?)?.toInt() ?? 420,
      noPk: json['noPk'] as String? ?? '',
      guardStatus: json['guardStatus'] as String? ?? 'Tetap',
      active: json['active'] as bool? ?? true,
    );
  }
}

String labelJawatan(String? value) {
  final raw = (value ?? '').trim();
  return switch (raw.toLowerCase()) {
    'management' => 'Admin Sistem',
    'administration' => 'Pentadbiran Syarikat',
    'supervisor' => 'Penyelia',
    'patrol' => 'Pengawal Rondaan',
    _ => raw.isEmpty ? '-' : raw,
  };
}
"""
write("lib/core/api/app_user.dart", app_user)


# ---------------------------------------------------------------------------
# Fix direct login: Administration must land on report-only dashboard.
# ---------------------------------------------------------------------------
p = "lib/features/auth/login_screen.dart"
t = read(p)
t = replace_once(
    t,
    "import '../dashboard/dashboard_screen.dart';\n",
    "import '../admin/report_only_dashboard_screen.dart';\nimport '../dashboard/dashboard_screen.dart';\n",
    "login report dashboard import",
)
t = replace_once(
    t,
    "          builder: (_) => NotificationAlertGate(\n            user: user,\n",
    "          builder: (_) => user.isAdministration\n              ? ReportOnlyDashboardScreen(\n                  user: user,\n                  api: _api,\n                  nfcService: widget.nfcService,\n                  mockMode: widget.mockMode,\n                )\n              : NotificationAlertGate(\n                  user: user,\n",
    "login administration route",
)
write(p, t)


# ---------------------------------------------------------------------------
# Report-only dashboard: company-level account, multi-school report access.
# ---------------------------------------------------------------------------
report_dashboard = """import 'package:flutter/material.dart';

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
        builder: (_) => LoginScreen(nfcService: nfcService, mockMode: mockMode),
      ),
      (_) => false,
    );
  }

  void _openReports(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportScreen(api: api, user: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final company = user.companyName.isEmpty ? 'Syarikat belum ditetapkan' : user.companyName;
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
                width: 92,
                height: 92,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              user.nama,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '${user.jawatanPaparan} • $company',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FutureBuilder<List<DepartmentRecord>>(
              future: api.getAdminDepartments(),
              builder: (context, snapshot) {
                final count = snapshot.data?.where((item) => item.active).length;
                final subtitle = count == null
                    ? 'Memuatkan senarai sekolah syarikat…'
                    : '$count sekolah di bawah akses syarikat ini';
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openReports(context),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.picture_as_pdf_rounded, size: 48),
                          const SizedBox(height: 14),
                          Text(
                            'Jana Laporan PDF',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 7),
                          Text(subtitle, textAlign: TextAlign.center),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: () => _openReports(context),
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Pilih Sekolah & Jana Laporan'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.account_tree_rounded),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Pentadbiran Syarikat boleh menjana laporan bagi semua sekolah yang dipautkan kepada syarikat yang sama. Fungsi rondaan dan konfigurasi sistem kekal dikunci.',
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
"""
write("lib/features/admin/report_only_dashboard_screen.dart", report_dashboard)


# ---------------------------------------------------------------------------
# Report screen: explicitly show company school scope and auto-pick single school.
# ---------------------------------------------------------------------------
report_screen = """import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/api/api_service.dart';
import '../../core/api/app_user.dart';
import 'pkk_pdf_generator.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({required this.api, this.user, super.key});

  final ApiService api;
  final AppUser? user;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  bool _generating = false;
  bool _loadingDepartments = true;
  String? _error;
  List<DepartmentRecord> _departments = const [];
  int? _departmentId;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final departments = await widget.api.getAdminDepartments();
      if (!mounted) return;
      final active = departments.where((item) => item.active).toList();
      setState(() {
        _departments = active;
        _loadingDepartments = false;
        if (_departmentId == null && active.length == 1) {
          _departmentId = active.first.id;
        }
        if (active.isEmpty) {
          _error = widget.user?.isAdministration == true
              ? 'Tiada sekolah dipautkan kepada syarikat akaun ini.'
              : 'Tiada sekolah aktif ditemui.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loadingDepartments = false;
      });
    }
  }

  DateTime get _from => DateTime(_year, _month, 1);
  DateTime get _to => DateTime(_year, _month + 1, 0);

  Future<Map<String, dynamic>> _reportData() async {
    if (_departmentId == null) {
      throw Exception('Pilih satu Sekolah sebelum menjana laporan PKK.');
    }
    return widget.api.getAdminReport(_from, _to, departmentId: _departmentId);
  }

  Future<void> _generate(_PkkType type) async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final data = await _reportData();
      final Uint8List bytes = switch (type) {
        _PkkType.pkk2 => await PkkPdfGenerator.generatePkk2(
          data: data,
          month: _month,
          year: _year,
        ),
        _PkkType.pkk3 => await PkkPdfGenerator.generatePkk3(
          data: data,
          month: _month,
          year: _year,
        ),
        _PkkType.pkk4 => await PkkPdfGenerator.generatePkk4(
          data: data,
          month: _month,
          year: _year,
        ),
      };
      if (bytes.isEmpty) throw Exception('Fail PDF tidak berjaya dijana.');

      final month = _month.toString().padLeft(2, '0');
      final school = _departments
          .where((item) => item.id == _departmentId)
          .map((item) => item.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_'))
          .firstOrNull;
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${type.filePrefix}_${school ?? 'SEKOLAH'}_${_year}_$month.pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${type.label} berjaya dijana sebagai PDF.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = List<int>.generate(
      DateTime.now().year - 2023,
      (index) => 2024 + index,
    ).reversed.toList();
    final isCompanyAdmin = widget.user?.isAdministration == true;
    final companyName = widget.user?.companyName ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Jana Laporan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Jana Laporan PKK',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isCompanyAdmin
                        ? 'Pilih mana-mana sekolah di bawah ${companyName.isEmpty ? 'syarikat anda' : companyName}, kemudian jana PKK 2, PKK 3 atau PKK 4.'
                        : 'Jana PKK 2, PKK 3 dan PKK 4 sebagai PDF berdasarkan data sebenar ZPatrol.',
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<int?>(
                    initialValue: _departmentId,
                    decoration: InputDecoration(
                      labelText: isCompanyAdmin
                          ? 'Sekolah Di Bawah Syarikat'
                          : 'Sekolah',
                      prefixIcon: const Icon(Icons.account_tree_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Pilih Sekolah'),
                      ),
                      ..._departments.map(
                        (department) => DropdownMenuItem<int?>(
                          value: department.id,
                          child: Text(department.name),
                        ),
                      ),
                    ],
                    onChanged: _loadingDepartments || _generating
                        ? null
                        : (value) => setState(() => _departmentId = value),
                  ),
                  if (isCompanyAdmin && _departments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_departments.length} sekolah tersedia untuk akaun ini.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _month,
                          decoration: const InputDecoration(
                            labelText: 'Bulan',
                            prefixIcon: Icon(Icons.calendar_month_rounded),
                          ),
                          items: [
                            for (var month = 1; month <= 12; month++)
                              DropdownMenuItem(
                                value: month,
                                child: Text(PkkPdfGenerator.months[month - 1]),
                              ),
                          ],
                          onChanged: _generating
                              ? null
                              : (value) => setState(() => _month = value ?? _month),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _year,
                          decoration: const InputDecoration(labelText: 'Tahun'),
                          items: years
                              .map(
                                (year) => DropdownMenuItem(
                                  value: year,
                                  child: Text('$year'),
                                ),
                              )
                              .toList(),
                          onChanged: _generating
                              ? null
                              : (value) => setState(() => _year = value ?? _year),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _ReportButton(
                    icon: Icons.groups_rounded,
                    title: 'Jana PKK 2 (PDF)',
                    subtitle: 'Pengesahan bilangan pengawal dan rekod kehadiran',
                    enabled: !_generating && !_loadingDepartments && _departmentId != null,
                    onPressed: () => _generate(_PkkType.pkk2),
                  ),
                  const SizedBox(height: 10),
                  _ReportButton(
                    icon: Icons.badge_rounded,
                    title: 'Jana PKK 3 (PDF)',
                    subtitle: 'Pengesahan kehadiran pengawal berdasarkan rekod kehadiran',
                    enabled: !_generating && !_loadingDepartments && _departmentId != null,
                    onPressed: () => _generate(_PkkType.pkk3),
                  ),
                  const SizedBox(height: 10),
                  _ReportButton(
                    icon: Icons.nfc_rounded,
                    title: 'Jana PKK 4 (PDF)',
                    subtitle: 'Pengesahan pelaksanaan rondaan dan clocking',
                    enabled: !_generating && !_loadingDepartments && _departmentId != null,
                    onPressed: () => _generate(_PkkType.pkk4),
                  ),
                  if (_generating) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text(
                      'Menjana PDF daripada data ZPatrol…',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PkkType {
  pkk2('PKK 2', 'PKK_2'),
  pkk3('PKK 3', 'PKK_3'),
  pkk4('PKK 4', 'PKK_4');

  const _PkkType(this.label, this.filePrefix);
  final String label;
  final String filePrefix;
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.picture_as_pdf_rounded),
        ],
      ),
    );
  }
}
"""
# firstOrNull is available in recent Dart core? Avoid dependency by replacing it below.
report_screen = report_screen.replace(
    "      final school = _departments\n          .where((item) => item.id == _departmentId)\n          .map((item) => item.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_'))\n          .firstOrNull;",
    "      String? school;\n      for (final item in _departments) {\n        if (item.id == _departmentId) {\n          school = item.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');\n          break;\n        }\n      }",
)
write("lib/features/admin/report_screen.dart", report_screen)


# ---------------------------------------------------------------------------
# Base worker: user/company identity + user edit inheritance.
# ---------------------------------------------------------------------------
p = "worker/index.js"
t = read(p)

user_select = """function userSelect() {
  return `SELECT u.id, u.nama, u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan, u.profile_picture,
                 u.jabatan, u.department_id, u.active,
                 COALESCE(d.name, u.jabatan) AS department_name,
                 COALESCE(u.company_id, d.company_id) AS company_id,
                 COALESCE(co.name, d.company_name, '') AS company_name,
                 COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,
                 COALESCE(d.session_start_minutes, 420) AS session_start_minutes
          FROM users u
          LEFT JOIN departments d ON d.id = u.department_id
          LEFT JOIN companies co ON co.id = COALESCE(u.company_id, d.company_id)`;
}"""
t = replace_js_function(t, "function userSelect() {", user_select, "index userSelect")

get_department = """async function getDepartmentById(env, id) {
  if (!Number.isInteger(Number(id)) || Number(id) <= 0) return null;
  return env.DB.prepare(
    `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            d.company_id, COALESCE(co.name, d.company_name, '') AS company_name,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN companies co ON co.id = d.company_id
     LEFT JOIN checkpoints c ON c.department_id = d.id
     WHERE d.id = ?
     GROUP BY d.id
     LIMIT 1`,
  ).bind(Number(id)).first();
}"""
t = replace_js_function(t, "async function getDepartmentById(env, id) {", get_department, "index getDepartmentById")

update_user = """async function updateAdminUser(request, env, userId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const nama = String(body.nama ?? '').trim().toUpperCase();
  const jawatan = String(body.jawatan ?? '').trim();
  const departmentId = Number(body.departmentId);
  const noPk = String(body.noPk ?? '').trim().slice(0, 50);
  const guardStatus = String(body.guardStatus ?? 'Tetap').trim();

  if (nama.length < 3) return json({ error: 'Nama pengguna tidak sah.' }, 400);
  if (!['Patrol', 'Supervisor', 'Administration', 'Management'].includes(jawatan)) {
    return json({ error: 'Jawatan pengguna tidak sah.' }, 400);
  }
  if (!['Tetap', 'Gantian'].includes(guardStatus)) {
    return json({ error: 'Status pengawal mesti Tetap atau Gantian.' }, 400);
  }

  const user = await getUserById(env, userId);
  if (!user) return json({ error: 'Pengguna tidak ditemui.' }, 404);

  let department = null;
  let resolvedDepartmentId = null;
  let companyId = null;
  let jabatan = user.jabatan || '';
  if (jawatan !== 'Management') {
    if (!Number.isInteger(departmentId) || departmentId <= 0) {
      return json({ error: 'Pilih Sekolah pengguna.' }, 400);
    }
    department = await env.DB.prepare(
      `SELECT d.id, d.name, d.company_id, COALESCE(c.name, d.company_name, '') AS company_name
       FROM departments d
       LEFT JOIN companies c ON c.id = d.company_id
       WHERE d.id = ? AND d.active = 1 LIMIT 1`,
    ).bind(departmentId).first();
    if (!department) return json({ error: 'Sekolah aktif tidak ditemui.' }, 404);
    if (jawatan === 'Administration' && !department.company_id) {
      return json({ error: 'Tetapkan Nama Syarikat pada Sekolah ini dahulu.' }, 409);
    }
    resolvedDepartmentId = Number(department.id);
    companyId = department.company_id == null ? null : Number(department.company_id);
    jabatan = jawatan === 'Administration'
      ? (department.company_name || department.name)
      : department.name;
  }

  let profilePicture = user.profile_picture || null;
  if (body.clearProfilePicture === true) {
    profilePicture = null;
  } else if (Object.prototype.hasOwnProperty.call(body, 'profilePicture')) {
    const picture = String(body.profilePicture ?? '');
    if (!/^data:image\\/(jpeg|png|webp);base64,/i.test(picture)) {
      return json({ error: 'Format gambar mesti JPEG, PNG atau WebP.' }, 400);
    }
    if (picture.length > 700000) {
      return json({ error: 'Gambar terlalu besar. Had selepas pemampatan ialah kira-kira 500 KB.' }, 413);
    }
    profilePicture = picture;
  }

  await env.DB.prepare(
    `UPDATE users
     SET nama = ?, jawatan = ?, department_id = ?, company_id = ?, jabatan = ?,
         profile_picture = ?, no_pk = ?, guard_status = ?
     WHERE id = ?`,
  ).bind(
    nama,
    jawatan,
    resolvedDepartmentId,
    companyId,
    jabatan,
    profilePicture,
    noPk || null,
    guardStatus,
    userId,
  ).run();

  const updated = await getUserById(env, userId);
  return json({ user: publicUser(updated) });
}"""
t = replace_js_function(t, "async function updateAdminUser(request, env, userId) {", update_user, "index updateAdminUser")

update_department = """async function updateUserDepartment(request, env, userId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const departmentId = Number(body.departmentId);
  const department = await getDepartmentById(env, departmentId);
  if (!department || Number(department.active) !== 1) {
    return json({ error: 'Sekolah aktif tidak ditemui.' }, 404);
  }

  const user = await getUserById(env, userId);
  if (!user) return json({ error: 'Pengguna tidak ditemui.' }, 404);
  const role = String(user.jawatan || '').trim().toLowerCase();
  const jabatan = role === 'administration'
    ? (department.company_name || department.name)
    : department.name;
  if (role === 'administration' && !department.company_id) {
    return json({ error: 'Tetapkan Nama Syarikat pada Sekolah ini dahulu.' }, 409);
  }

  await env.DB.prepare(
    'UPDATE users SET department_id = ?, company_id = ?, jabatan = ? WHERE id = ?',
  ).bind(
    departmentId,
    department.company_id ?? null,
    jabatan,
    userId,
  ).run();
  const updated = await getUserById(env, userId);
  return json({ user: publicUser(updated) });
}"""
t = replace_js_function(t, "async function updateUserDepartment(request, env, userId) {", update_department, "index updateUserDepartment")

public_user = """function publicUser(user) {
  return {
    id: Number(user.id),
    nama: user.nama,
    noKadPengenalan: user.no_kad_pengenalan,
    noPk: user.no_pk || '',
    guardStatus: user.guard_status || 'Tetap',
    jawatan: user.jawatan,
    profilePicture: user.profile_picture,
    jabatan: user.department_name || user.jabatan || user.company_name || 'Belum ditetapkan',
    departmentId: user.department_id == null ? null : Number(user.department_id),
    companyId: user.company_id == null ? null : Number(user.company_id),
    companyName: user.company_name || '',
    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),
    sessionStartMinutes: Number(user.session_start_minutes ?? 420),
    active: user.active === undefined ? true : Boolean(user.active),
  };
}"""
t = replace_js_function(t, "function publicUser(user) {", public_user, "index publicUser")
write(p, t)


# ---------------------------------------------------------------------------
# Smart worker: create users with inherited company and enforce company reports.
# ---------------------------------------------------------------------------
p = "worker/app.js"
t = read(p)

create_user = """async function createUser(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const nama = String(body.nama ?? '').trim().toUpperCase();
  const identityCard = String(body.noKadPengenalan ?? '').replace(/\\D/g, '');
  const jawatan = String(body.jawatan ?? 'Patrol').trim();
  const departmentId = Number(body.departmentId ?? 0);
  const noPk = String(body.noPk ?? '').trim().slice(0, 50);
  const guardStatus = String(body.guardStatus ?? 'Tetap').trim();

  if (nama.length < 3) return json({ error: 'Nama pengguna tidak sah.' }, 400);
  if (!/^\\d{12}$/.test(identityCard)) {
    return json({ error: 'No. Kad Pengenalan mesti mengandungi 12 digit.' }, 400);
  }
  if (!['Patrol', 'Supervisor', 'Administration', 'Management'].includes(jawatan)) {
    return json({ error: 'Jawatan mesti Patrol, Supervisor, Administration atau Management.' }, 400);
  }
  if (!['Tetap', 'Gantian'].includes(guardStatus)) {
    return json({ error: 'Status pengawal mesti Tetap atau Gantian.' }, 400);
  }

  let department = null;
  let resolvedDepartmentId = null;
  let companyId = null;
  let jabatan = 'Pengurusan Sistem';
  if (jawatan !== 'Management') {
    if (!Number.isInteger(departmentId) || departmentId <= 0) {
      return json({ error: 'Pilih Sekolah pengguna.' }, 400);
    }
    department = await env.DB.prepare(
      `SELECT d.id, d.name, d.company_id, COALESCE(c.name, d.company_name, '') AS company_name
       FROM departments d
       LEFT JOIN companies c ON c.id = d.company_id
       WHERE d.id = ? AND d.active = 1 LIMIT 1`,
    ).bind(departmentId).first();
    if (!department) return json({ error: 'Sekolah tidak ditemui atau tidak aktif.' }, 404);
    if (jawatan === 'Administration' && !department.company_id) {
      return json({ error: 'Tetapkan Nama Syarikat pada Sekolah ini dahulu.' }, 409);
    }
    resolvedDepartmentId = Number(department.id);
    companyId = department.company_id == null ? null : Number(department.company_id);
    jabatan = jawatan === 'Administration'
      ? (department.company_name || department.name)
      : department.name;
  }

  const duplicate = await env.DB.prepare(
    'SELECT id FROM users WHERE no_kad_pengenalan = ? LIMIT 1',
  ).bind(identityCard).first();
  if (duplicate) return json({ error: 'No. Kad Pengenalan ini sudah berdaftar.' }, 409);

  const result = await env.DB.prepare(
    `INSERT INTO users (
       nama, no_kad_pengenalan, no_pk, guard_status, jawatan, profile_picture,
       jabatan, active, department_id, company_id
     ) VALUES (?, ?, ?, ?, ?, NULL, ?, 1, ?, ?)`,
  ).bind(
    nama,
    identityCard,
    noPk || null,
    guardStatus,
    jawatan,
    jabatan,
    resolvedDepartmentId,
    companyId,
  ).run();

  const user = await getUserById(env, result.meta?.last_row_id);
  return json({ user: publicUser(user) }, 201);
}"""
t = replace_js_function(t, "async function createUser(request, env) {", create_user, "app createUser")

old_scope = """  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const ownDepartmentId = Number(auth.user.department_id || 0) || null;
  const rawDepartmentId = url.searchParams.get('departmentId');
  let departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);
  if (role === 'administration') {
    if (!ownDepartmentId) {
      return json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Sekolah.' }, 409);
    }
    if (departmentId != null && departmentId !== ownDepartmentId) {
      return json({ error: 'Pentadbiran Syarikat hanya boleh memuat turun laporan lokasi sendiri.' }, 403);
    }
    departmentId = ownDepartmentId;
  }
"""
new_scope = """  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const companyId = Number(auth.user.company_id || 0) || null;
  const rawDepartmentId = url.searchParams.get('departmentId');
  let departmentId = rawDepartmentId == null ? null : Number(rawDepartmentId);
  if (role === 'administration') {
    if (!companyId) {
      return json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Syarikat.' }, 409);
    }
    if (departmentId == null) {
      return json({ error: 'Pilih Sekolah laporan.' }, 400);
    }
    const allowedDepartment = await env.DB.prepare(
      'SELECT id FROM departments WHERE id = ? AND company_id = ? AND active = 1 LIMIT 1',
    ).bind(departmentId, companyId).first();
    if (!allowedDepartment) {
      return json({ error: 'Sekolah ini tidak berada di bawah syarikat akaun anda.' }, 403);
    }
  }
"""
t = replace_once(t, old_scope, new_scope, "company-scoped adminReport")

require_user = """async function requireUser(request, env) {
  const token = getSessionToken(request);
  if (!token) return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };

  const user = await env.DB.prepare(
    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan, u.profile_picture,
            u.jabatan, u.active, u.department_id,
            COALESCE(u.company_id, d.company_id) AS company_id,
            COALESCE(co.name, d.company_name, '') AS company_name,
            COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,
            COALESCE(d.session_start_minutes, 420) AS session_start_minutes
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     LEFT JOIN departments d ON d.id = u.department_id
     LEFT JOIN companies co ON co.id = COALESCE(u.company_id, d.company_id)
     WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
     LIMIT 1`,
  ).bind(await sha256(token), Date.now()).first();

  if (!user) return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  return { user };
}"""
t = replace_js_function(t, "async function requireUser(request, env) {", require_user, "app requireUser")

get_user = """async function getUserById(env, id) {
  return env.DB.prepare(
    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan, u.profile_picture,
            u.jabatan, u.active, u.department_id,
            COALESCE(u.company_id, d.company_id) AS company_id,
            COALESCE(co.name, d.company_name, '') AS company_name,
            COALESCE(d.name, u.jabatan) AS department_name,
            COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,
            COALESCE(d.session_start_minutes, 420) AS session_start_minutes
     FROM users u
     LEFT JOIN departments d ON d.id = u.department_id
     LEFT JOIN companies co ON co.id = COALESCE(u.company_id, d.company_id)
     WHERE u.id = ? LIMIT 1`,
  ).bind(id).first();
}"""
t = replace_js_function(t, "async function getUserById(env, id) {", get_user, "app getUserById")

public_user_app = """function publicUser(user) {
  return {
    id: user.id,
    nama: user.nama,
    noKadPengenalan: user.no_kad_pengenalan,
    noPk: user.no_pk || '',
    guardStatus: user.guard_status || 'Tetap',
    jawatan: user.jawatan,
    profilePicture: user.profile_picture,
    jabatan: user.department_name || user.jabatan || user.company_name || 'Belum ditetapkan',
    active: Boolean(user.active),
    departmentId: user.department_id == null ? null : Number(user.department_id),
    companyId: user.company_id == null ? null : Number(user.company_id),
    companyName: user.company_name || '',
    sessionIntervalMinutes: Number(user.session_interval_minutes || 120),
    sessionStartMinutes: Number(user.session_start_minutes ?? 420),
  };
}"""
t = replace_js_function(t, "function publicUser(user) {", public_user_app, "app publicUser")
write(p, t)


# ---------------------------------------------------------------------------
# Attendance/admin department worker: normalize company names and scope schools.
# ---------------------------------------------------------------------------
p = "worker/attendance.js"
t = read(p)

admin_departments = """async function adminDepartments(request, env) {
  const auth = await requireReportAccess(request, env);
  if (auth.response) return auth.response;
  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  const scopeCompanyId = role === 'administration'
    ? Number(auth.user.company_id || 0) || null
    : null;
  if (role === 'administration' && !scopeCompanyId) {
    return json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Syarikat.' }, 409);
  }

  const sql = `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            d.attendance_latitude, d.attendance_longitude, d.attendance_radius_m,
            d.attendance_location_label, d.company_id,
            COALESCE(co.name, d.company_name, '') AS company_name, d.zone,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN companies co ON co.id = d.company_id
     LEFT JOIN checkpoints c ON c.department_id = d.id
     WHERE d.active = 1 ${scopeCompanyId ? 'AND d.company_id = ?' : ''}
     GROUP BY d.id
     ORDER BY d.name ASC`;
  const result = scopeCompanyId
    ? await env.DB.prepare(sql).bind(scopeCompanyId).all()
    : await env.DB.prepare(sql).all();
  return json({ departments: (result.results ?? []).map(departmentJson) });
}"""
t = replace_js_function(t, "async function adminDepartments(request, env) {", admin_departments, "attendance adminDepartments")

create_department = """async function createDepartment(request, env) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const parsed = validateDepartmentBody(body);
  if (parsed.error) return json({ error: parsed.error }, 400);
  const duplicate = await env.DB.prepare(
    'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND active = 1 LIMIT 1',
  ).bind(parsed.name).first();
  if (duplicate) return json({ error: 'Sekolah dengan nama ini sudah wujud.' }, 409);
  const company = await resolveCompany(env, parsed.companyName);
  const result = await env.DB.prepare(
    `INSERT INTO departments (
       name, session_interval_minutes, session_start_minutes, active, updated_at,
       attendance_latitude, attendance_longitude, attendance_radius_m, attendance_location_label,
       company_id, company_name, zone
     ) VALUES (?, ?, ?, 1, CURRENT_TIMESTAMP, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    parsed.name,
    parsed.interval,
    parsed.startMinutes,
    parsed.latitude,
    parsed.longitude,
    parsed.radius,
    parsed.locationLabel,
    company?.id ?? null,
    company?.name ?? parsed.companyName || null,
    parsed.zone || null,
  ).run();
  return json({ department: departmentJson(await getDepartment(env, result.meta?.last_row_id)) }, 201);
}"""
t = replace_js_function(t, "async function createDepartment(request, env) {", create_department, "attendance createDepartment")

update_department_fn = """async function updateDepartment(request, env, departmentId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const parsed = validateDepartmentBody(body);
  if (parsed.error) return json({ error: parsed.error }, 400);
  const active = body.active === false ? 0 : 1;
  const existing = await getDepartment(env, departmentId);
  if (!existing) return json({ error: 'Sekolah tidak ditemui.' }, 404);
  const duplicate = await env.DB.prepare(
    'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND id <> ? AND active = 1 LIMIT 1',
  ).bind(parsed.name, departmentId).first();
  if (duplicate) return json({ error: 'Sekolah dengan nama ini sudah wujud.' }, 409);
  const company = await resolveCompany(env, parsed.companyName);
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE departments SET
         name = ?, session_interval_minutes = ?, session_start_minutes = ?, active = ?,
         attendance_latitude = ?, attendance_longitude = ?, attendance_radius_m = ?,
         attendance_location_label = ?, company_id = ?, company_name = ?, zone = ?,
         updated_at = CURRENT_TIMESTAMP
       WHERE id = ?`,
    ).bind(
      parsed.name,
      parsed.interval,
      parsed.startMinutes,
      active,
      parsed.latitude,
      parsed.longitude,
      parsed.radius,
      parsed.locationLabel,
      company?.id ?? null,
      company?.name ?? parsed.companyName || null,
      parsed.zone || null,
      departmentId,
    ),
    env.DB.prepare(
      'UPDATE users SET jabatan = CASE WHEN LOWER(jawatan) = ? THEN ? ELSE ? END, company_id = ? WHERE department_id = ?',
    ).bind(
      'administration',
      company?.name ?? parsed.companyName || parsed.name,
      parsed.name,
      company?.id ?? null,
      departmentId,
    ),
  ]);
  return json({ department: departmentJson(await getDepartment(env, departmentId)) });
}"""
t = replace_js_function(t, "async function updateDepartment(request, env, departmentId) {", update_department_fn, "attendance updateDepartment")

validate_department = """function validateDepartmentBody(body) {
  const name = String(body.name ?? '').trim();
  const interval = Number(body.sessionIntervalMinutes ?? 120);
  const startMinutes = Number(body.sessionStartMinutes ?? 420);
  const latitude = Number(body.attendanceLatitude);
  const longitude = Number(body.attendanceLongitude);
  const radius = Number(body.attendanceRadiusMeters ?? DEFAULT_RADIUS_M);
  const locationLabel = String(body.attendanceLocationLabel ?? '').trim().slice(0, 160);
  const companyName = String(body.companyName ?? '').trim().slice(0, 180);
  const zone = String(body.zone ?? '').trim().slice(0, 100);
  if (name.length < 2) return { error: 'Nama Sekolah terlalu pendek.' };
  if (!Number.isInteger(interval) || interval < 15 || interval > 1440) {
    return { error: 'Tempoh sesi mesti antara 15 hingga 1440 minit.' };
  }
  if (!Number.isInteger(startMinutes) || startMinutes < 0 || startMinutes > 1439) {
    return { error: 'Jam mula sesi tidak sah.' };
  }
  if (!validCoordinate(latitude, longitude)) {
    return { error: 'Tandakan pusat kawasan sekolah pada peta.' };
  }
  if (!Number.isFinite(radius) || radius < 30 || radius > 1000) {
    return { error: 'Radius kehadiran mesti antara 30m hingga 1000m.' };
  }
  return {
    name,
    interval,
    startMinutes,
    latitude,
    longitude,
    radius: Math.round(radius),
    locationLabel,
    companyName,
    zone,
  };
}"""
t = replace_js_function(t, "function validateDepartmentBody(body) {", validate_department, "attendance validateDepartmentBody")

resolve_company = """async function resolveCompany(env, rawName) {
  const name = String(rawName || '').trim();
  if (!name) return null;
  let company = await env.DB.prepare(
    'SELECT id, name FROM companies WHERE LOWER(name) = LOWER(?) LIMIT 1',
  ).bind(name).first();
  if (company) return company;
  try {
    await env.DB.prepare(
      'INSERT INTO companies (name, active, updated_at) VALUES (?, 1, CURRENT_TIMESTAMP)',
    ).bind(name).run();
  } catch (_) {
    // Another concurrent request may have created the same company.
  }
  company = await env.DB.prepare(
    'SELECT id, name FROM companies WHERE LOWER(name) = LOWER(?) LIMIT 1',
  ).bind(name).first();
  return company;
}"""
marker = "function validateDepartmentBody(body) {"
if "async function resolveCompany(env, rawName)" not in t:
    if marker not in t:
        raise RuntimeError("resolveCompany insertion anchor missing")
    t = t.replace(marker, resolve_company + "\n\n" + marker, 1)

get_department_att = """async function getDepartment(env, id) {
  if (!Number.isInteger(Number(id)) || Number(id) <= 0) return null;
  return env.DB.prepare(
    `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,
            d.attendance_latitude, d.attendance_longitude, d.attendance_radius_m,
            d.attendance_location_label, d.company_id,
            COALESCE(co.name, d.company_name, '') AS company_name, d.zone,
            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count
     FROM departments d
     LEFT JOIN companies co ON co.id = d.company_id
     LEFT JOIN checkpoints c ON c.department_id = d.id
     WHERE d.id = ?
     GROUP BY d.id LIMIT 1`,
  ).bind(Number(id)).first();
}"""
t = replace_js_function(t, "async function getDepartment(env, id) {", get_department_att, "attendance getDepartment")

department_json = """function departmentJson(row) {
  return {
    id: Number(row.id),
    name: row.name,
    sessionIntervalMinutes: Number(row.session_interval_minutes || 120),
    sessionStartMinutes: Number(row.session_start_minutes ?? 420),
    active: Number(row.active) === 1,
    checkpointCount: Number(row.checkpoint_count || 0),
    attendanceLatitude: row.attendance_latitude == null ? null : Number(row.attendance_latitude),
    attendanceLongitude: row.attendance_longitude == null ? null : Number(row.attendance_longitude),
    attendanceRadiusMeters: Number(row.attendance_radius_m || DEFAULT_RADIUS_M),
    attendanceLocationLabel: row.attendance_location_label || '',
    companyId: row.company_id == null ? null : Number(row.company_id),
    companyName: row.company_name || '',
    zone: row.zone || '',
  };
}"""
t = replace_js_function(t, "function departmentJson(row) {", department_json, "attendance departmentJson")

require_user_att = """async function requireUser(request, env) {
  const token = getSessionToken(request);
  if (!token) return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };
  const user = await env.DB.prepare(
    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.jawatan, u.profile_picture,
            u.jabatan, u.active, u.department_id,
            COALESCE(u.company_id, d.company_id) AS company_id,
            COALESCE(co.name, d.company_name, '') AS company_name,
            COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes
     FROM sessions s
     JOIN users u ON u.id = s.user_id
     LEFT JOIN departments d ON d.id = u.department_id
     LEFT JOIN companies co ON co.id = COALESCE(u.company_id, d.company_id)
     WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
     LIMIT 1`,
  ).bind(await sha256(token), Date.now()).first();
  if (!user) return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  return { user };
}"""
t = replace_js_function(t, "async function requireUser(request, env) {", require_user_att, "attendance requireUser")
write(p, t)


# ---------------------------------------------------------------------------
# PDF metadata should use the normalized company name.
# ---------------------------------------------------------------------------
p = "worker/reports.js"
t = read(p)
t = replace_once(
    t,
    "  const departmentMeta = departmentId == null ? null : await env.DB.prepare(\n    'SELECT id, name, company_name, zone FROM departments WHERE id = ? LIMIT 1',\n  ).bind(departmentId).first();\n",
    "  const departmentMeta = departmentId == null ? null : await env.DB.prepare(\n    `SELECT d.id, d.name, COALESCE(c.name, d.company_name, '') AS company_name, d.zone\n     FROM departments d\n     LEFT JOIN companies c ON c.id = d.company_id\n     WHERE d.id = ? LIMIT 1`,\n  ).bind(departmentId).first();\n",
    "normalized report company metadata",
)
write(p, t)


# ---------------------------------------------------------------------------
# Version bump for rebuilt mobile clients.
# ---------------------------------------------------------------------------
p = "pubspec.yaml"
t = read(p)
t = re.sub(r"^version:\s*[^\n]+", "version: 0.8.0+41", t, count=1, flags=re.M)
write(p, t)


# ---------------------------------------------------------------------------
# Update access-control documentation.
# ---------------------------------------------------------------------------
doc = """# ZPatrol - Matriks Akses & Hierarki Syarikat

## Hierarki baharu

`Admin Sistem -> Syarikat -> Banyak Sekolah -> Penyelia / Pengawal Rondaan`

Satu syarikat boleh mengendalikan banyak sekolah. Nama syarikat pada tetapan Sekolah dinormalisasikan kepada rekod `companies`, setiap sekolah mempunyai `company_id`, dan pengguna mewarisi `company_id` daripada sekolah utama mereka.

## Peranan

| Peranan | Kod | Skop |
| --- | --- | --- |
| Admin Sistem | `Management` | Akses penuh merentas semua syarikat dan sekolah. |
| Pentadbiran Syarikat | `Administration` | Laporan PDF sahaja untuk semua sekolah di bawah syarikat yang sama. |
| Penyelia | `Supervisor` | Operasi dan pemantauan sekolah sendiri. |
| Pengawal Rondaan | `Patrol` | Operasi rondaan sekolah sendiri. |

## Pentadbiran Syarikat

- Log masuk terus ke dashboard laporan khas.
- Boleh melihat senarai semua sekolah yang berkongsi `company_id` yang sama.
- Boleh memilih mana-mana sekolah tersebut dan menjana PKK 2, PKK 3 atau PKK 4.
- Backend mengesahkan bahawa `department_id` laporan benar-benar berada di bawah `company_id` akaun tersebut.
- API operasi lain kekal disekat.

## Sekatan akaun

Hanya `Management` boleh memanggil `PUT /api/admin/users/:id/status`. Menyekat akaun menetapkan `active = 0` dan memadam sesi aktif pengguna. Login dan sesi sedia ada ditolak sehingga Admin Sistem menyahsekat akaun.
"""
write("docs/ZPATROL_ACCESS_CONTROL.md", doc)

print("Applied ZPatrol multi-school company hierarchy patch.")
