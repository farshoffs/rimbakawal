#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Marker tidak ditemui [{label}] dalam {path}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_all(path: Path, old: str, new: str, label: str, minimum: int = 1) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count < minimum:
        raise SystemExit(f'Marker tidak cukup [{label}] dalam {path}: {count}')
    path.write_text(text.replace(old, new), encoding='utf-8')


# -----------------------------------------------------------------------------
# D1 migration: status pengawal Tetap / Gantian. Existing guards default Tetap,
# and the current BUFFER account is explicitly set to Gantian.
# -----------------------------------------------------------------------------
migration = ROOT / 'migrations/0017_guard_status.sql'
migration.write_text(
    """-- Status pengawal untuk Borang PKK 2 dan pentadbiran pengguna.\n"
    "ALTER TABLE users ADD COLUMN guard_status TEXT NOT NULL DEFAULT 'Tetap';\n\n"
    "UPDATE users\n"
    "SET guard_status = 'Gantian'\n"
    "WHERE UPPER(TRIM(nama)) = 'BUFFER';\n"
    """,
    encoding='utf-8',
)

# -----------------------------------------------------------------------------
# Flutter model.
# -----------------------------------------------------------------------------
app_user = ROOT / 'lib/core/api/app_user.dart'
replace_once(
    app_user,
    "    this.noPk = '',\n    this.active = true,\n",
    "    this.noPk = '',\n    this.guardStatus = 'Tetap',\n    this.active = true,\n",
    'AppUser constructor guard status',
)
replace_once(
    app_user,
    "  final String noPk;\n  final bool active;\n",
    "  final String noPk;\n  final String guardStatus;\n  final bool active;\n",
    'AppUser field guard status',
)
replace_once(
    app_user,
    "      noPk: json['noPk'] as String? ?? '',\n      active: json['active'] as bool? ?? true,\n",
    "      noPk: json['noPk'] as String? ?? '',\n      guardStatus: json['guardStatus'] as String? ?? 'Tetap',\n      active: json['active'] as bool? ?? true,\n",
    'AppUser JSON guard status',
)

# -----------------------------------------------------------------------------
# Flutter API client.
# -----------------------------------------------------------------------------
api = ROOT / 'lib/core/api/api_service.dart'
replace_once(
    api,
    "    required int departmentId,\n    String noPk = '',\n  }) async {\n",
    "    required int departmentId,\n    String noPk = '',\n    String guardStatus = 'Tetap',\n  }) async {\n",
    'createAdminUser signature',
)
replace_once(
    api,
    "          'departmentId': departmentId,\n          'noPk': noPk,\n",
    "          'departmentId': departmentId,\n          'noPk': noPk,\n          'guardStatus': guardStatus,\n",
    'createAdminUser payload',
)
replace_once(
    api,
    "    required int departmentId,\n    String noPk = '',\n    String? profilePicture,\n",
    "    required int departmentId,\n    String noPk = '',\n    String guardStatus = 'Tetap',\n    String? profilePicture,\n",
    'updateAdminUser signature',
)
replace_once(
    api,
    "      'departmentId': departmentId,\n      'noPk': noPk,\n    };\n",
    "      'departmentId': departmentId,\n      'noPk': noPk,\n      'guardStatus': guardStatus,\n    };\n",
    'updateAdminUser payload',
)

# -----------------------------------------------------------------------------
# Admin user UI: Tetap/Gantian dropdown for edit + add user.
# -----------------------------------------------------------------------------
ui = ROOT / 'lib/features/admin/user_maintenance_screen.dart'
replace_once(
    ui,
    "  late String _jawatan;\n  int? _departmentId;\n",
    "  late String _jawatan;\n  late String _guardStatus;\n  int? _departmentId;\n",
    'edit state guard status',
)
replace_once(
    ui,
    "    _jawatan = widget.user.jawatan;\n    _departmentId = widget.user.departmentId;\n",
    "    _jawatan = widget.user.jawatan;\n    _guardStatus = widget.user.guardStatus;\n    _departmentId = widget.user.departmentId;\n",
    'edit init guard status',
)
replace_once(
    ui,
    "        noPk: _noPkController.text.trim(),\n        profilePicture: _newProfilePicture,\n",
    "        noPk: _noPkController.text.trim(),\n        guardStatus: _guardStatus,\n        profilePicture: _newProfilePicture,\n",
    'edit save guard status',
)
replace_once(
    ui,
    "                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n${user.jawatanPaparan} • ${user.jabatan}',\n",
    "                                '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n${user.jawatanPaparan} • ${user.guardStatus} • ${user.jabatan}',\n",
    'user list status label',
)
replace_once(
    ui,
    "  String _jawatan = 'Patrol';\n  int? _departmentId;\n",
    "  String _jawatan = 'Patrol';\n  String _guardStatus = 'Tetap';\n  int? _departmentId;\n",
    'add state guard status',
)
replace_once(
    ui,
    "        noPk: _noPkController.text.trim(),\n      );\n",
    "        noPk: _noPkController.text.trim(),\n        guardStatus: _guardStatus,\n      );\n",
    'add save guard status',
)

status_dropdown = """              DropdownButtonFormField<String>(
                initialValue: _guardStatus,
                decoration: const InputDecoration(
                  labelText: 'Status Pengawal',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                  helperText: 'Digunakan pada ruangan TETAP / GANTIAN Borang PKK 2.',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Tetap',
                    child: Text('Tetap'),
                  ),
                  DropdownMenuItem(
                    value: 'Gantian',
                    child: Text('Gantian'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _guardStatus = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
"""
marker = """              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _departmentId,
"""
# Edit dialog.
replace_once(
    ui,
    marker,
    "              const SizedBox(height: 12),\n" + status_dropdown +
    "              DropdownButtonFormField<int>(\n                initialValue: _departmentId,\n",
    'edit guard status dropdown',
)
# Add dialog.
replace_once(
    ui,
    marker,
    "              const SizedBox(height: 12),\n" + status_dropdown +
    "              DropdownButtonFormField<int>(\n                initialValue: _departmentId,\n",
    'add guard status dropdown',
)

# -----------------------------------------------------------------------------
# Base worker: GET/PUT admin user + login/session payload.
# -----------------------------------------------------------------------------
index = ROOT / 'worker/index.js'
replace_once(
    index,
    "  const noPk = String(body.noPk ?? '').trim().slice(0, 50);\n\n  if (nama.length < 3)",
    "  const noPk = String(body.noPk ?? '').trim().slice(0, 50);\n  const guardStatus = String(body.guardStatus ?? 'Tetap').trim();\n\n  if (nama.length < 3)",
    'index parse guard status',
)
replace_once(
    index,
    "  if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan pengguna tidak sah.' }, 400);\n  }\n",
    "  if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan pengguna tidak sah.' }, 400);\n  }\n  if (!['Tetap', 'Gantian'].includes(guardStatus)) {\n    return json({ error: 'Status pengawal mesti Tetap atau Gantian.' }, 400);\n  }\n",
    'index validate guard status',
)
replace_once(
    index,
    "     SET nama = ?, jawatan = ?, department_id = ?, jabatan = ?, profile_picture = ?, no_pk = ?\n     WHERE id = ?`,\n  ).bind(nama, jawatan, departmentId, department.name, profilePicture, noPk || null, userId).run();\n",
    "     SET nama = ?, jawatan = ?, department_id = ?, jabatan = ?, profile_picture = ?, no_pk = ?, guard_status = ?\n     WHERE id = ?`,\n  ).bind(nama, jawatan, departmentId, department.name, profilePicture, noPk || null, guardStatus, userId).run();\n",
    'index persist guard status',
)
replace_once(
    index,
    "  return `SELECT u.id, u.nama, u.no_kad_pengenalan, u.no_pk, u.jawatan, u.profile_picture,\n",
    "  return `SELECT u.id, u.nama, u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan, u.profile_picture,\n",
    'index userSelect guard status',
)
replace_once(
    index,
    "    noPk: user.no_pk || '',\n    jawatan: user.jawatan,\n",
    "    noPk: user.no_pk || '',\n    guardStatus: user.guard_status || 'Tetap',\n    jawatan: user.jawatan,\n",
    'index publicUser guard status',
)

# -----------------------------------------------------------------------------
# App worker: POST create user + its local user/session serializers.
# -----------------------------------------------------------------------------
app = ROOT / 'worker/app.js'
replace_once(
    app,
    "  const noPk = String(body.noPk ?? '').trim().slice(0, 50);\n\n  if (nama.length < 3)",
    "  const noPk = String(body.noPk ?? '').trim().slice(0, 50);\n  const guardStatus = String(body.guardStatus ?? 'Tetap').trim();\n\n  if (nama.length < 3)",
    'app parse guard status',
)
replace_once(
    app,
    "  if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan mesti Patrol, Supervisor atau Management.' }, 400);\n  }\n",
    "  if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {\n    return json({ error: 'Jawatan mesti Patrol, Supervisor atau Management.' }, 400);\n  }\n  if (!['Tetap', 'Gantian'].includes(guardStatus)) {\n    return json({ error: 'Status pengawal mesti Tetap atau Gantian.' }, 400);\n  }\n",
    'app validate guard status',
)
replace_once(
    app,
    "    `INSERT INTO users (nama, no_kad_pengenalan, no_pk, jawatan, profile_picture, jabatan, active, department_id)\n     VALUES (?, ?, ?, ?, NULL, ?, 1, ?)`,\n  ).bind(nama, identityCard, noPk || null, jawatan, department.name, departmentId).run();\n",
    "    `INSERT INTO users (nama, no_kad_pengenalan, no_pk, guard_status, jawatan, profile_picture, jabatan, active, department_id)\n     VALUES (?, ?, ?, ?, ?, NULL, ?, 1, ?)`,\n  ).bind(nama, identityCard, noPk || null, guardStatus, jawatan, department.name, departmentId).run();\n",
    'app create guard status',
)
replace_all(
    app,
    "u.no_kad_pengenalan, u.no_pk, u.jawatan, u.profile_picture,",
    "u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan, u.profile_picture,",
    'app selects guard status',
    minimum=2,
)
replace_once(
    app,
    "    noPk: user.no_pk || '',\n    jawatan: user.jawatan,\n",
    "    noPk: user.no_pk || '',\n    guardStatus: user.guard_status || 'Tetap',\n    jawatan: user.jawatan,\n",
    'app publicUser guard status',
)

# -----------------------------------------------------------------------------
# Report API: expose guard_status to PKK generator.
# -----------------------------------------------------------------------------
reports = ROOT / 'worker/reports.js'
replace_all(
    reports,
    "u.nama, u.no_kad_pengenalan, u.no_pk, u.jawatan,",
    "u.nama, u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan,",
    'report scan/attendance guard status',
    minimum=2,
)
replace_once(
    reports,
    "      `SELECT id, nama, no_kad_pengenalan, no_pk, jawatan\n",
    "      `SELECT id, nama, no_kad_pengenalan, no_pk, guard_status, jawatan\n",
    'report guard list select',
)
replace_once(
    reports,
    "    no_pk: row.no_pk || '',\n    jawatan: row.jawatan || 'patrol',\n",
    "    no_pk: row.no_pk || '',\n    guard_status: row.guard_status || 'Tetap',\n    jawatan: row.jawatan || 'patrol',\n",
    'report guard payload status',
)

# -----------------------------------------------------------------------------
# PKK 2 PDF: mark X under Tetap or Gantian according to stored status.
# -----------------------------------------------------------------------------
pdf = ROOT / 'lib/features/admin/pkk_pdf_generator.dart'
replace_once(
    pdf,
    "                    pw.Expanded(\n                      child: sideCell(\n                        index < guards.length ? 'X' : '',\n                        height: 9,\n                      ),\n                    ),\n                    pw.Expanded(child: sideCell('', height: 9)),\n",
    "                    pw.Expanded(\n                      child: sideCell(\n                        index < guards.length && !guards[index].isReplacement\n                            ? 'X'\n                            : '',\n                        height: 9,\n                      ),\n                    ),\n                    pw.Expanded(\n                      child: sideCell(\n                        index < guards.length && guards[index].isReplacement\n                            ? 'X'\n                            : '',\n                        height: 9,\n                      ),\n                    ),\n",
    'PKK2 Tetap/Gantian marks',
)
replace_once(
    pdf,
    "        noPk: (row['no_pk'] ?? '').toString(),\n      );\n",
    "        noPk: (row['no_pk'] ?? '').toString(),\n        guardStatus: (row['guard_status'] ?? 'Tetap').toString(),\n      );\n",
    'PKK guard list status',
)
replace_once(
    pdf,
    "          noPk: session.noPk,\n        ),\n",
    "          noPk: session.noPk,\n          guardStatus: session.guardStatus,\n        ),\n",
    'PKK session fallback status',
)
replace_once(
    pdf,
    "      noPk: (input['no_pk'] ?? '').toString(),\n      start: start,\n",
    "      noPk: (input['no_pk'] ?? '').toString(),\n      guardStatus: (input['guard_status'] ?? 'Tetap').toString(),\n      start: start,\n",
    'PKK session input status',
)
replace_once(
    pdf,
    "class _GuardMeta {\n  const _GuardMeta({required this.id, required this.name, required this.noPk});\n  final int id;\n  final String name;\n  final String noPk;\n}\n",
    "class _GuardMeta {\n  const _GuardMeta({\n    required this.id,\n    required this.name,\n    required this.noPk,\n    this.guardStatus = 'Tetap',\n  });\n  final int id;\n  final String name;\n  final String noPk;\n  final String guardStatus;\n\n  bool get isReplacement => guardStatus.trim().toLowerCase() == 'gantian';\n}\n",
    'GuardMeta status field',
)
replace_once(
    pdf,
    "    required this.noPk,\n    required this.start,\n",
    "    required this.noPk,\n    this.guardStatus = 'Tetap',\n    required this.start,\n",
    'GuardSession constructor status',
)
replace_once(
    pdf,
    "  final String noPk;\n  final DateTime start;\n",
    "  final String noPk;\n  final String guardStatus;\n  final DateTime start;\n",
    'GuardSession field status',
)

# Version bump for production builds.
pubspec = ROOT / 'pubspec.yaml'
text = pubspec.read_text(encoding='utf-8')
if 'version: 0.6.0+37' in text:
    text = text.replace('version: 0.6.0+37', 'version: 0.6.1+38', 1)
elif 'version: 0.6.1+38' not in text:
    raise SystemExit('Versi pubspec tidak dijangka.')
pubspec.write_text(text, encoding='utf-8')

print('Applied Tetap/Gantian guard status feature and BUFFER migration.')
