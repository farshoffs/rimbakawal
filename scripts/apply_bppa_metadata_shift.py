from pathlib import Path


def patch(path, changes):
    p = Path(path)
    text = p.read_text()
    for old, new in changes:
        if old not in text:
            raise SystemExit(f'missing marker in {path}: {old[:120]!r}')
        text = text.replace(old, new, 1)
    p.write_text(text)

patch('lib/core/api/app_user.dart', [
    ("    this.sessionStartMinutes = 420,\n    this.active = true,\n", "    this.sessionStartMinutes = 420,\n    this.noPk = '',\n    this.active = true,\n"),
    ("  final int sessionStartMinutes;\n  final bool active;\n", "  final int sessionStartMinutes;\n  final String noPk;\n  final bool active;\n"),
    ("      sessionStartMinutes:\n          (json['sessionStartMinutes'] as num?)?.toInt() ?? 420,\n      active: json['active'] as bool? ?? true,\n", "      sessionStartMinutes:\n          (json['sessionStartMinutes'] as num?)?.toInt() ?? 420,\n      noPk: json['noPk'] as String? ?? '',\n      active: json['active'] as bool? ?? true,\n"),
])

patch('lib/core/api/api_service.dart', [
    ("    this.attendanceLocationLabel = '',\n  });\n", "    this.attendanceLocationLabel = '',\n    this.companyName = '',\n    this.zone = '',\n  });\n"),
    ("  final String attendanceLocationLabel;\n\n  factory DepartmentRecord.fromJson", "  final String attendanceLocationLabel;\n  final String companyName;\n  final String zone;\n\n  factory DepartmentRecord.fromJson"),
    ("        attendanceLocationLabel: json['attendanceLocationLabel'] as String? ?? '',\n      );\n", "        attendanceLocationLabel: json['attendanceLocationLabel'] as String? ?? '',\n        companyName: json['companyName'] as String? ?? '',\n        zone: json['zone'] as String? ?? '',\n      );\n"),
    ("    required int departmentId,\n  }) async {\n", "    required int departmentId,\n    String noPk = '',\n  }) async {\n",),
    ("          'departmentId': departmentId,\n        }),\n", "          'departmentId': departmentId,\n          'noPk': noPk,\n        }),\n",),
    ("    String attendanceLocationLabel = '',\n  }) async {\n", "    String attendanceLocationLabel = '',\n    String companyName = '',\n    String zone = '',\n  }) async {\n"),
    ("          'attendanceLocationLabel': attendanceLocationLabel,\n        }),\n", "          'attendanceLocationLabel': attendanceLocationLabel,\n          'companyName': companyName,\n          'zone': zone,\n        }),\n",),
    ("          'attendanceLocationLabel': department.attendanceLocationLabel,\n        }),\n", "          'attendanceLocationLabel': department.attendanceLocationLabel,\n          'companyName': department.companyName,\n          'zone': department.zone,\n        }),\n",),
    ("    required int departmentId,\n    String? profilePicture,\n", "    required int departmentId,\n    String noPk = '',\n    String? profilePicture,\n"),
    ("      'departmentId': departmentId,\n    };\n", "      'departmentId': departmentId,\n      'noPk': noPk,\n    };\n"),
])

patch('lib/features/profile/profile_screen.dart', [
    ("          _InfoTile(label: 'No. Kad Pengenalan', value: _user.noKadPengenalan),\n", "          _InfoTile(label: 'No. Kad Pengenalan', value: _user.noKadPengenalan),\n          _InfoTile(label: 'No. PK', value: _user.noPk.isEmpty ? '-' : _user.noPk),\n"),
])

patch('lib/features/admin/user_maintenance_screen.dart', [
    ("  late final TextEditingController _nameController;\n  late String _jawatan;\n", "  late final TextEditingController _nameController;\n  late final TextEditingController _noPkController;\n  late String _jawatan;\n"),
    ("    _nameController = TextEditingController(text: widget.user.nama);\n    _jawatan = widget.user.jawatan;\n", "    _nameController = TextEditingController(text: widget.user.nama);\n    _noPkController = TextEditingController(text: widget.user.noPk);\n    _jawatan = widget.user.jawatan;\n"),
    ("    _nameController.dispose();\n    super.dispose();\n", "    _nameController.dispose();\n    _noPkController.dispose();\n    super.dispose();\n",),
    ("        departmentId: _departmentId!,\n        profilePicture: _newProfilePicture,\n", "        departmentId: _departmentId!,\n        noPk: _noPkController.text.trim(),\n        profilePicture: _newProfilePicture,\n"),
    ("              const SizedBox(height: 12),\n              DropdownButtonFormField<String>(\n", "              const SizedBox(height: 12),\n              TextField(\n                controller: _noPkController,\n                decoration: const InputDecoration(\n                  labelText: 'No. PK',\n                  prefixIcon: Icon(Icons.numbers_rounded),\n                  helperText: 'Nombor pengawal untuk borang BPPA PKK 2.',\n                ),\n              ),\n              const SizedBox(height: 12),\n              DropdownButtonFormField<String>(\n",),
    ("  final _icController = TextEditingController();\n  String _jawatan = 'Patrol';\n", "  final _icController = TextEditingController();\n  final _noPkController = TextEditingController();\n  String _jawatan = 'Patrol';\n"),
    ("    _icController.dispose();\n    super.dispose();\n", "    _icController.dispose();\n    _noPkController.dispose();\n    super.dispose();\n"),
    ("        departmentId: _departmentId!,\n      );\n", "        departmentId: _departmentId!,\n        noPk: _noPkController.text.trim(),\n      );\n",),
    ("              const SizedBox(height: 12),\n              DropdownButtonFormField<String>(\n                initialValue: _jawatan,\n", "              const SizedBox(height: 12),\n              TextField(\n                controller: _noPkController,\n                decoration: const InputDecoration(\n                  labelText: 'No. PK',\n                  prefixIcon: Icon(Icons.numbers_rounded),\n                ),\n              ),\n              const SizedBox(height: 12),\n              DropdownButtonFormField<String>(\n                initialValue: _jawatan,\n",),
    ("                    '${user.noKadPengenalan}\\n${user.jawatanPaparan} • ${user.jabatan}',\n", "                    '${user.noKadPengenalan}${user.noPk.isEmpty ? '' : ' • No. PK ${user.noPk}'}\\n${user.jawatanPaparan} • ${user.jabatan}',\n"),
])

patch('lib/features/admin/department_maintenance_screen.dart', [
    ("  late final TextEditingController _locationLabelController;\n", "  late final TextEditingController _locationLabelController;\n  late final TextEditingController _companyController;\n  late final TextEditingController _zoneController;\n"),
    ("    _locationLabelController = TextEditingController(text: widget.department?.attendanceLocationLabel ?? '');\n", "    _locationLabelController = TextEditingController(text: widget.department?.attendanceLocationLabel ?? '');\n    _companyController = TextEditingController(text: widget.department?.companyName ?? '');\n    _zoneController = TextEditingController(text: widget.department?.zone ?? '');\n"),
    ("    _locationLabelController.dispose();\n    super.dispose();\n", "    _locationLabelController.dispose();\n    _companyController.dispose();\n    _zoneController.dispose();\n    super.dispose();\n"),
    ("          attendanceLocationLabel: _locationLabelController.text.trim(),\n        );\n", "          attendanceLocationLabel: _locationLabelController.text.trim(),\n          companyName: _companyController.text.trim(),\n          zone: _zoneController.text.trim(),\n        );\n"),
    ("            attendanceLocationLabel: _locationLabelController.text.trim(),\n          ),\n", "            attendanceLocationLabel: _locationLabelController.text.trim(),\n            companyName: _companyController.text.trim(),\n            zone: _zoneController.text.trim(),\n          ),\n"),
    ("              const SizedBox(height: 14),\n              TextField(\n                controller: _intervalController,\n", "              const SizedBox(height: 14),\n              TextField(\n                controller: _companyController,\n                textCapitalization: TextCapitalization.characters,\n                decoration: const InputDecoration(\n                  labelText: 'Nama Syarikat',\n                  prefixIcon: Icon(Icons.business_rounded),\n                  helperText: 'Digunakan dalam borang BPPA PKK 2 dan PKK 3.',\n                ),\n              ),\n              const SizedBox(height: 14),\n              TextField(\n                controller: _zoneController,\n                textCapitalization: TextCapitalization.characters,\n                decoration: const InputDecoration(\n                  labelText: 'Zon',\n                  prefixIcon: Icon(Icons.map_outlined),\n                  helperText: 'Digunakan dalam borang BPPA PKK 2 dan PKK 3.',\n                ),\n              ),\n              const SizedBox(height: 14),\n              TextField(\n                controller: _intervalController,\n"),
    ("                    'Mula ${TimeOfDay(hour: department.sessionStartMinutes ~/ 60, minute: department.sessionStartMinutes % 60).format(context)} • '\n", "                    '${department.companyName.isEmpty ? '' : '${department.companyName} • '}${department.zone.isEmpty ? '' : 'Zon ${department.zone} • '}'\n                    'Mula ${TimeOfDay(hour: department.sessionStartMinutes ~/ 60, minute: department.sessionStartMinutes % 60).format(context)} • '\n"),
])

patch('worker/index.js', [
    ("  const departmentId = Number(body.departmentId);\n\n  if (nama.length < 3)", "  const departmentId = Number(body.departmentId);\n  const noPk = String(body.noPk ?? '').trim().slice(0, 50);\n\n  if (nama.length < 3)"),
    ("     SET nama = ?, jawatan = ?, department_id = ?, jabatan = ?, profile_picture = ?\n     WHERE id = ?`,\n  ).bind(nama, jawatan, departmentId, department.name, profilePicture, userId).run();\n", "     SET nama = ?, jawatan = ?, department_id = ?, jabatan = ?, profile_picture = ?, no_pk = ?\n     WHERE id = ?`,\n  ).bind(nama, jawatan, departmentId, department.name, profilePicture, noPk || null, userId).run();\n"),
    ("  return `SELECT u.id, u.nama, u.no_kad_pengenalan, u.jawatan, u.profile_picture,\n", "  return `SELECT u.id, u.nama, u.no_kad_pengenalan, u.no_pk, u.jawatan, u.profile_picture,\n"),
    ("    noKadPengenalan: user.no_kad_pengenalan,\n    jawatan: user.jawatan,\n", "    noKadPengenalan: user.no_kad_pengenalan,\n    noPk: user.no_pk || '',\n    jawatan: user.jawatan,\n"),
])

patch('worker/app.js', [
    ("  const jawatan = String(body.jawatan ?? 'Patrol').trim();\n  const departmentId = Number(body.departmentId ?? 0);\n", "  const jawatan = String(body.jawatan ?? 'Patrol').trim();\n  const departmentId = Number(body.departmentId ?? 0);\n  const noPk = String(body.noPk ?? '').trim().slice(0, 50);\n"),
    ("    `INSERT INTO users (nama, no_kad_pengenalan, jawatan, profile_picture, jabatan, active, department_id)\n     VALUES (?, ?, ?, NULL, ?, 1, ?)`,\n  ).bind(nama, identityCard, jawatan, department.name, departmentId).run();\n", "    `INSERT INTO users (nama, no_kad_pengenalan, no_pk, jawatan, profile_picture, jabatan, active, department_id)\n     VALUES (?, ?, ?, ?, NULL, ?, 1, ?)`,\n  ).bind(nama, identityCard, noPk || null, jawatan, department.name, departmentId).run();\n"),
    ("    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.jawatan, u.profile_picture,\n            u.jabatan, u.active, u.department_id,\n", "    `SELECT u.id, u.nama, u.no_kad_pengenalan, u.no_pk, u.jawatan, u.profile_picture,\n            u.jabatan, u.active, u.department_id,\n"),
    ("    noKadPengenalan: user.no_kad_pengenalan,\n    jawatan: user.jawatan,\n", "    noKadPengenalan: user.no_kad_pengenalan,\n    noPk: user.no_pk || '',\n    jawatan: user.jawatan,\n"),
])

patch('worker/attendance.js', [
    ("            d.attendance_location_label,\n            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count\n", "            d.attendance_location_label, d.company_name, d.zone,\n            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count\n"),
    ("       attendance_latitude, attendance_longitude, attendance_radius_m, attendance_location_label\n     ) VALUES (?, ?, ?, 1, CURRENT_TIMESTAMP, ?, ?, ?, ?)`,\n", "       attendance_latitude, attendance_longitude, attendance_radius_m, attendance_location_label,\n       company_name, zone\n     ) VALUES (?, ?, ?, 1, CURRENT_TIMESTAMP, ?, ?, ?, ?, ?, ?)`,\n"),
    ("    parsed.locationLabel,\n  ).run();\n", "    parsed.locationLabel,\n    parsed.companyName || null,\n    parsed.zone || null,\n  ).run();\n",),
    ("         attendance_location_label = ?, updated_at = CURRENT_TIMESTAMP\n       WHERE id = ?`,\n", "         attendance_location_label = ?, company_name = ?, zone = ?, updated_at = CURRENT_TIMESTAMP\n       WHERE id = ?`,\n"),
    ("      parsed.locationLabel,\n      departmentId,\n", "      parsed.locationLabel,\n      parsed.companyName || null,\n      parsed.zone || null,\n      departmentId,\n"),
    ("  const locationLabel = String(body.attendanceLocationLabel ?? '').trim().slice(0, 160);\n", "  const locationLabel = String(body.attendanceLocationLabel ?? '').trim().slice(0, 160);\n  const companyName = String(body.companyName ?? '').trim().slice(0, 180);\n  const zone = String(body.zone ?? '').trim().slice(0, 100);\n"),
    ("  return { name, interval, startMinutes, latitude, longitude, radius: Math.round(radius), locationLabel };\n", "  return { name, interval, startMinutes, latitude, longitude, radius: Math.round(radius), locationLabel, companyName, zone };\n"),
    ("            d.attendance_location_label,\n            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count\n", "            d.attendance_location_label, d.company_name, d.zone,\n            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count\n"),
    ("    attendanceLocationLabel: row.attendance_location_label || '',\n  };\n", "    attendanceLocationLabel: row.attendance_location_label || '',\n    companyName: row.company_name || '',\n    zone: row.zone || '',\n  };\n"),
])

patch('worker/reports.js', [
    ("              u.nama, u.no_kad_pengenalan, u.jawatan,\n", "              u.nama, u.no_kad_pengenalan, u.no_pk, u.jawatan,\n"),
    ("              u.nama, u.no_kad_pengenalan, u.jawatan,\n              COALESCE(d.name, u.jabatan) AS jabatan\n", "              u.nama, u.no_kad_pengenalan, u.no_pk, u.jawatan,\n              COALESCE(d.name, u.jabatan) AS jabatan\n"),
    ("  const [scanResult, attendanceResult] = await Promise.all([\n", "  const departmentMeta = departmentId == null ? null : await env.DB.prepare(\n    'SELECT id, name, company_name, zone FROM departments WHERE id = ? LIMIT 1',\n  ).bind(departmentId).first();\n\n  const [scanResult, attendanceResult] = await Promise.all([\n"),
    ("  payload.scans = scanResult.results ?? [];\n", "  if (departmentMeta) {\n    payload.department = {\n      id: Number(departmentMeta.id),\n      name: departmentMeta.name,\n      companyName: departmentMeta.company_name || '',\n      zone: departmentMeta.zone || '',\n    };\n  }\n  payload.scans = scanResult.results ?? [];\n"),
])

patch('lib/features/admin/report_screen.dart', [
    ("            () => _AttendanceDayRow(name: row['nama']?.toString() ?? '-', firstPunch: punchedAt),\n", "            () => _AttendanceDayRow(\n              name: row['nama']?.toString() ?? '-',\n              noPk: row['no_pk']?.toString() ?? '',\n              firstPunch: punchedAt,\n            ),\n"),
    ("        document.addPage(_pkk2Page(document, department['name']?.toString() ?? '', 1, 12, rowsByDay));\n        document.addPage(_pkk2Page(document, department['name']?.toString() ?? '', 13, 24, rowsByDay));\n        document.addPage(_pkk2Page(document, department['name']?.toString() ?? '', 25, 31, rowsByDay));\n", "        final institution = department['name']?.toString() ?? '';\n        final companyName = department['companyName']?.toString() ?? '';\n        final zone = department['zone']?.toString() ?? '';\n        document.addPage(_pkk2Page(document, institution, companyName, zone, 1, 12, rowsByDay));\n        document.addPage(_pkk2Page(document, institution, companyName, zone, 13, 24, rowsByDay));\n        document.addPage(_pkk2Page(document, institution, companyName, zone, 25, 31, rowsByDay));\n"),
    ("    String institution,\n    int startDay,\n", "    String institution,\n    String companyName,\n    String zone,\n    int startDay,\n"),
    ("                  _cell('', height: 10.6),\n                  _cell('', align: pw.Alignment.center, height: 10.6),\n", "                  _cell(guard?.noPk ?? '', height: 10.6),\n                  _cell(guard == null ? '' : _shiftCode(guard.firstPunch), align: pw.Alignment.center, height: 10.6),\n"),
    ("                pw.Expanded(child: _fieldLine('NAMA SYARIKAT :', '')),\n                pw.SizedBox(width: 80),\n                pw.Expanded(child: _fieldLine('ZON :', '')),\n", "                pw.Expanded(child: _fieldLine('NAMA SYARIKAT :', companyName)),\n                pw.SizedBox(width: 80),\n                pw.Expanded(child: _fieldLine('ZON :', zone)),\n"),
    ("              department['name']?.toString() ?? '',\n              monday,\n", "              department['name']?.toString() ?? '',\n              department['companyName']?.toString() ?? '',\n              department['zone']?.toString() ?? '',\n              monday,\n"),
    ("  pw.Page _pkk3Page(\n    String institution,\n    DateTime monday,\n", "  pw.Page _pkk3Page(\n    String institution,\n    String companyName,\n    String zone,\n    DateTime monday,\n"),
    ("                pw.Expanded(child: _fieldLine('NAMA SYARIKAT :', '')),\n                pw.SizedBox(width: 55),\n                pw.Expanded(child: _fieldLine('ZON :', '')),\n", "                pw.Expanded(child: _fieldLine('NAMA SYARIKAT :', companyName)),\n                pw.SizedBox(width: 55),\n                pw.Expanded(child: _fieldLine('ZON :', zone)),\n"),
    ("  String _checkpointLine(Map<String, dynamic> row) {\n", "  String _shiftCode(DateTime clocking) {\n    return clocking.hour >= 7 && clocking.hour < 19 ? '1' : '2';\n  }\n\n  String _checkpointLine(Map<String, dynamic> row) {\n"),
    ("                    'Nota: Borang BPPA memerlukan satu Jabatan. Medan NAMA SYARIKAT, ZON, NO. PK dan SYIF dibiarkan kosong kerana RimbaKawal belum mempunyai medan khusus tersebut.',\n", "                    'Nota: NAMA SYARIKAT dan ZON diambil daripada Tetapan Jabatan. NO. PK diambil daripada Profil Pengguna. SYIF ditentukan automatik: 1-SIANG bagi 07:00–18:59 dan 2-MALAM bagi 19:00–06:59.',\n"),
    ("class _AttendanceDayRow {\n  _AttendanceDayRow({required this.name, required this.firstPunch});\n\n  final String name;\n", "class _AttendanceDayRow {\n  _AttendanceDayRow({required this.name, required this.noPk, required this.firstPunch});\n\n  final String name;\n  final String noPk;\n"),
])
