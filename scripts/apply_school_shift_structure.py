from pathlib import Path
import re


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 occurrence, found {count}')
    return text.replace(old, new, 1)

# ---------------------------------------------------------------------------
# Flutter API model/service
# ---------------------------------------------------------------------------
p = Path('lib/core/api/api_service.dart')
t = p.read_text(encoding='utf-8')

shift_class = '''class DepartmentShiftRecord {
  const DepartmentShiftRecord({
    required this.shiftNumber,
    required this.startMinutes,
    required this.endMinutes,
    required this.requiredGuards,
  });

  final int shiftNumber;
  final int startMinutes;
  final int endMinutes;
  final int requiredGuards;

  factory DepartmentShiftRecord.fromJson(Map<String, dynamic> json) =>
      DepartmentShiftRecord(
        shiftNumber: (json['shiftNumber'] as num?)?.toInt() ?? 1,
        startMinutes: (json['startMinutes'] as num?)?.toInt() ?? 480,
        endMinutes: (json['endMinutes'] as num?)?.toInt() ?? 1200,
        requiredGuards: (json['requiredGuards'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'shiftNumber': shiftNumber,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
    'requiredGuards': requiredGuards,
  };
}

'''
t = replace_once(t, 'class DepartmentRecord {\n', shift_class + 'class DepartmentRecord {\n', 'insert shift class')
t = replace_once(t, "    this.zone = '',\n  });", "    this.zone = '',\n    this.shifts = const [],\n  });", 'department ctor shifts')
t = replace_once(t, '  final String zone;\n\n  factory DepartmentRecord.fromJson(', '  final String zone;\n  final List<DepartmentShiftRecord> shifts;\n\n  int get shiftCount => shifts.length;\n\n  factory DepartmentRecord.fromJson(', 'department fields shifts')
t = replace_once(t, "    zone: json['zone'] as String? ?? '',\n  );", "    zone: json['zone'] as String? ?? '',\n    shifts: (json['shifts'] as List<dynamic>? ?? const [])\n        .map(\n          (item) => DepartmentShiftRecord.fromJson(\n            Map<String, dynamic>.from(item as Map),\n          ),\n        )\n        .toList(),\n  );", 'department json shifts')

# createDepartment signature and payload
t = replace_once(t, "    int? companyId,\n    String zone = '',\n  }) async {", "    int? companyId,\n    String zone = '',\n    List<DepartmentShiftRecord> shifts = const [],\n  }) async {", 'createDepartment shifts arg')
t = replace_once(t, "          'companyId': companyId,\n          'zone': zone,\n        }),", "          'companyId': companyId,\n          'zone': zone,\n          'shifts': shifts.map((item) => item.toJson()).toList(),\n        }),", 'createDepartment shifts payload')

# updateDepartment payload: match the later occurrence only via exact adjacent block
t = replace_once(t, "          'companyId': department.companyId,\n          'zone': department.zone,\n        }),", "          'companyId': department.companyId,\n          'zone': department.zone,\n          'shifts': department.shifts.map((item) => item.toJson()).toList(),\n        }),", 'updateDepartment shifts payload')

p.write_text(t, encoding='utf-8')

# ---------------------------------------------------------------------------
# School settings UI
# ---------------------------------------------------------------------------
p = Path('lib/features/admin/department_maintenance_screen.dart')
t = p.read_text(encoding='utf-8')

t = replace_once(t, "                    'Sesi setiap ${department.sessionIntervalMinutes} minit • '\n", "                    '${department.shiftCount} syif • '\n                    'Sesi setiap ${department.sessionIntervalMinutes} minit • '\n", 'school subtitle shift count')

t = replace_once(t, "  late TimeOfDay _startTime;\n  late bool _active;", "  late TimeOfDay _startTime;\n  late List<int> _shiftStartMinutes;\n  late List<int> _shiftEndMinutes;\n  late List<int> _shiftRequiredGuards;\n  late bool _active;", 'ui shift state fields')

anchor = """    final startMinutes = widget.department?.sessionStartMinutes ?? 420;
    _startTime = TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);
    _active = widget.department?.active ?? true;"""
replacement = """    final startMinutes = widget.department?.sessionStartMinutes ?? 420;
    _startTime = TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);
    final configuredShifts = widget.department?.shifts ?? const <DepartmentShiftRecord>[];
    final initialShifts = configuredShifts.isEmpty
        ? const <DepartmentShiftRecord>[
            DepartmentShiftRecord(
              shiftNumber: 1,
              startMinutes: 480,
              endMinutes: 1200,
              requiredGuards: 0,
            ),
            DepartmentShiftRecord(
              shiftNumber: 2,
              startMinutes: 1200,
              endMinutes: 480,
              requiredGuards: 0,
            ),
          ]
        : configuredShifts;
    _shiftStartMinutes = initialShifts.map((item) => item.startMinutes).toList();
    _shiftEndMinutes = initialShifts.map((item) => item.endMinutes).toList();
    _shiftRequiredGuards = initialShifts.map((item) => item.requiredGuards).toList();
    _active = widget.department?.active ?? true;"""
t = replace_once(t, anchor, replacement, 'ui init shifts')

pick_anchor = """  Future<void> _pickStartTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _startTime,
      helpText: 'Pilih masa mula sesi rondaan',
    );
    if (selected != null && mounted) setState(() => _startTime = selected);
  }
"""
pick_replacement = pick_anchor + """
  String _minutesLabel(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  Future<void> _pickShiftTime(int index, {required bool start}) async {
    final value = start ? _shiftStartMinutes[index] : _shiftEndMinutes[index];
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
      helpText: start ? 'Masa mula Syif ${index + 1}' : 'Masa tamat Syif ${index + 1}',
    );
    if (selected == null || !mounted) return;
    final minutes = selected.hour * 60 + selected.minute;
    setState(() {
      if (start) {
        _shiftStartMinutes[index] = minutes;
      } else {
        _shiftEndMinutes[index] = minutes;
      }
    });
  }

  void _setShiftCount(int count) {
    setState(() {
      while (_shiftStartMinutes.length < count) {
        final index = _shiftStartMinutes.length;
        final defaults = index == 2 ? <int>[0, 480] : <int>[480, 1200];
        _shiftStartMinutes.add(defaults[0]);
        _shiftEndMinutes.add(defaults[1]);
        _shiftRequiredGuards.add(0);
      }
      if (_shiftStartMinutes.length > count) {
        _shiftStartMinutes = _shiftStartMinutes.take(count).toList();
        _shiftEndMinutes = _shiftEndMinutes.take(count).toList();
        _shiftRequiredGuards = _shiftRequiredGuards.take(count).toList();
      }
    });
  }

  List<DepartmentShiftRecord> _shiftRecords() => [
    for (var index = 0; index < _shiftStartMinutes.length; index++)
      DepartmentShiftRecord(
        shiftNumber: index + 1,
        startMinutes: _shiftStartMinutes[index],
        endMinutes: _shiftEndMinutes[index],
        requiredGuards: _shiftRequiredGuards[index],
      ),
  ];
"""
t = replace_once(t, pick_anchor, pick_replacement, 'ui shift helpers')

# Inject validation before saving flag
save_anchor = """    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.department;"""
save_replacement = """    for (var index = 0; index < _shiftStartMinutes.length; index++) {
      if (_shiftStartMinutes[index] == _shiftEndMinutes[index]) {
        setState(() => _error = 'Masa mula dan tamat Syif ${index + 1} tidak boleh sama.');
        return;
      }
      if (_shiftRequiredGuards[index] < 0 || _shiftRequiredGuards[index] > 99) {
        setState(() => _error = 'Bilangan pengawal Syif ${index + 1} mesti antara 0 hingga 99.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.department;"""
t = replace_once(t, save_anchor, save_replacement, 'ui shift validation')

# Save create and update
t = replace_once(t, "          companyId: _companyId,\n          zone: _zoneController.text.trim(),\n        );", "          companyId: _companyId,\n          zone: _zoneController.text.trim(),\n          shifts: _shiftRecords(),\n        );", 'ui create save shifts')
t = replace_once(t, "            companyName: existing.companyName,\n            zone: _zoneController.text.trim(),\n          ),", "            companyName: existing.companyName,\n            zone: _zoneController.text.trim(),\n            shifts: _shiftRecords(),\n          ),", 'ui update save shifts')

ui_anchor = """              const SizedBox(height: 16),
              Text(
                'Kawasan Kehadiran',"""
ui_block = """              const SizedBox(height: 16),
              Text(
                'Tetapan Syif PKK',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tetapkan bilangan syif, masa bertugas dan bilangan pengawal kontrak secara manual. Tetapan ini digunakan terus dalam PKK 2.',
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _shiftStartMinutes.length,
                decoration: const InputDecoration(
                  labelText: 'Bilangan Syif',
                  prefixIcon: Icon(Icons.work_history_outlined),
                  helperText: 'PKK 2 akan memaparkan hanya syif yang aktif pada jadual kehadiran.',
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 Syif')),
                  DropdownMenuItem(value: 2, child: Text('2 Syif')),
                  DropdownMenuItem(value: 3, child: Text('3 Syif')),
                ],
                onChanged: _saving ? null : (value) {
                  if (value != null) _setShiftCount(value);
                },
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < _shiftStartMinutes.length; index++) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Syif ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _saving ? null : () => _pickShiftTime(index, start: true),
                                icon: const Icon(Icons.login_rounded),
                                label: Text('Mula ${_minutesLabel(_shiftStartMinutes[index])}'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _saving ? null : () => _pickShiftTime(index, start: false),
                                icon: const Icon(Icons.logout_rounded),
                                label: Text('Tamat ${_minutesLabel(_shiftEndMinutes[index])}'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: ValueKey('required-guards-$index-${_shiftRequiredGuards[index]}'),
                          initialValue: '${_shiftRequiredGuards[index]}',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Bilangan Pengawal Dalam Kontrak',
                            prefixIcon: Icon(Icons.groups_2_outlined),
                            helperText: 'Tidak dikira daripada kehadiran. Masukkan nilai kontrak secara manual.',
                          ),
                          onChanged: (value) {
                            _shiftRequiredGuards[index] = int.tryParse(value) ?? 0;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              Text(
                'Kawasan Kehadiran',"""
t = replace_once(t, ui_anchor, ui_block, 'ui shift section')

p.write_text(t, encoding='utf-8')

# ---------------------------------------------------------------------------
# Worker: school settings persistence and serialization
# ---------------------------------------------------------------------------
p = Path('worker/attendance.js')
t = p.read_text(encoding='utf-8')

# adminDepartments response with shift rows
old = """  const result = await env.DB.prepare(sql).bind(...binds).all();
  return json({ departments: (result.results ?? []).map(departmentJson) });
}"""
new = """  const [result, shiftResult] = await Promise.all([
    env.DB.prepare(sql).bind(...binds).all(),
    env.DB.prepare(
      `SELECT department_id, shift_number, start_minutes, end_minutes, required_guards
         FROM department_shifts
        WHERE active = 1
        ORDER BY department_id ASC, shift_number ASC`,
    ).all(),
  ]);
  const shiftsByDepartment = new Map();
  for (const shift of shiftResult.results ?? []) {
    const departmentId = Number(shift.department_id);
    const list = shiftsByDepartment.get(departmentId) ?? [];
    list.push(shift);
    shiftsByDepartment.set(departmentId, list);
  }
  return json({
    departments: (result.results ?? []).map((row) =>
      departmentJson(row, shiftsByDepartment.get(Number(row.id)) ?? [])),
  });
}"""
t = replace_once(t, old, new, 'worker adminDepartments shifts')

# create insert: after result, save shifts
old = """  ).run();
  return json({ department: departmentJson(await getDepartment(env, result.meta?.last_row_id)) }, 201);
}"""
new = """  ).run();
  const departmentId = Number(result.meta?.last_row_id || 0);
  await replaceDepartmentShifts(env, departmentId, parsed.shifts ?? defaultDepartmentShifts());
  return json({ department: departmentJson(await getDepartment(env, departmentId)) }, 201);
}"""
t = replace_once(t, old, new, 'worker create save shifts')

# update after batch
old = """  ]);
  return json({ department: departmentJson(await getDepartment(env, departmentId)) });
}"""
new = """  ]);
  if (parsed.shifts != null) {
    await replaceDepartmentShifts(env, departmentId, parsed.shifts);
  }
  return json({ department: departmentJson(await getDepartment(env, departmentId)) });
}"""
t = replace_once(t, old, new, 'worker update save shifts')

# validate body: add shift parsing before validation and return
t = replace_once(t, "  const zone = String(body.zone ?? '').trim().slice(0, 100);\n", "  const zone = String(body.zone ?? '').trim().slice(0, 100);\n  const shiftResult = normalizeDepartmentShifts(body.shifts);\n  if (shiftResult.error) return { error: shiftResult.error };\n", 'worker parse shifts')
t = replace_once(t, "    companyName,\n    zone,\n  };", "    companyName,\n    zone,\n    shifts: shiftResult.shifts,\n  };", 'worker return shifts')

# getDepartment query -> attach shifts
old = """async function getDepartment(env, id) {
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
}

function departmentJson(row) {
"""
new = """async function getDepartment(env, id) {
  if (!Number.isInteger(Number(id)) || Number(id) <= 0) return null;
  const departmentId = Number(id);
  const [row, shifts] = await Promise.all([
    env.DB.prepare(
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
    ).bind(departmentId).first(),
    env.DB.prepare(
      `SELECT department_id, shift_number, start_minutes, end_minutes, required_guards
         FROM department_shifts
        WHERE department_id = ? AND active = 1
        ORDER BY shift_number ASC`,
    ).bind(departmentId).all(),
  ]);
  if (!row) return null;
  row._shifts = shifts.results ?? [];
  return row;
}

function departmentJson(row, shifts = row?._shifts ?? []) {
"""
t = replace_once(t, old, new, 'worker getDepartment shifts')

t = replace_once(t, "    zone: row.zone || '',\n  };", "    zone: row.zone || '',\n    shifts: shifts.map(shiftJson),\n  };", 'worker department json shifts')

# helpers before attendanceJson
helper_anchor = """function attendanceJson(row) {
"""
helpers = """function defaultDepartmentShifts() {
  return [
    { shiftNumber: 1, startMinutes: 480, endMinutes: 1200, requiredGuards: 0 },
    { shiftNumber: 2, startMinutes: 1200, endMinutes: 480, requiredGuards: 0 },
  ];
}

function normalizeDepartmentShifts(raw) {
  if (raw == null) return { shifts: null };
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > 3) {
    return { error: 'Bilangan syif mesti antara 1 hingga 3.' };
  }
  const shifts = [];
  const seen = new Set();
  for (const item of raw) {
    const shiftNumber = Number(item?.shiftNumber);
    const startMinutes = Number(item?.startMinutes);
    const endMinutes = Number(item?.endMinutes);
    const requiredGuards = Number(item?.requiredGuards ?? 0);
    if (!Number.isInteger(shiftNumber) || shiftNumber < 1 || shiftNumber > 3 || seen.has(shiftNumber)) {
      return { error: 'Nombor syif tidak sah.' };
    }
    if (!Number.isInteger(startMinutes) || startMinutes < 0 || startMinutes > 1439 ||
        !Number.isInteger(endMinutes) || endMinutes < 0 || endMinutes > 1439 ||
        startMinutes === endMinutes) {
      return { error: `Masa Syif ${shiftNumber} tidak sah.` };
    }
    if (!Number.isInteger(requiredGuards) || requiredGuards < 0 || requiredGuards > 99) {
      return { error: `Bilangan pengawal Syif ${shiftNumber} mesti antara 0 hingga 99.` };
    }
    seen.add(shiftNumber);
    shifts.push({ shiftNumber, startMinutes, endMinutes, requiredGuards });
  }
  shifts.sort((a, b) => a.shiftNumber - b.shiftNumber);
  for (let index = 0; index < shifts.length; index++) {
    if (shifts[index].shiftNumber !== index + 1) {
      return { error: 'Syif mesti disusun berturutan bermula dari Syif 1.' };
    }
  }
  return { shifts };
}

async function replaceDepartmentShifts(env, departmentId, shifts) {
  const statements = [
    env.DB.prepare('DELETE FROM department_shifts WHERE department_id = ?').bind(departmentId),
  ];
  for (const shift of shifts) {
    statements.push(
      env.DB.prepare(
        `INSERT INTO department_shifts (
           department_id, shift_number, start_minutes, end_minutes, required_guards, active, updated_at
         ) VALUES (?, ?, ?, ?, ?, 1, CURRENT_TIMESTAMP)`,
      ).bind(
        departmentId,
        shift.shiftNumber,
        shift.startMinutes,
        shift.endMinutes,
        shift.requiredGuards,
      ),
    );
  }
  await env.DB.batch(statements);
}

function shiftJson(row) {
  return {
    shiftNumber: Number(row.shift_number),
    startMinutes: Number(row.start_minutes),
    endMinutes: Number(row.end_minutes),
    requiredGuards: Number(row.required_guards || 0),
  };
}

function attendanceJson(row) {
"""
t = replace_once(t, helper_anchor, helpers, 'worker shift helpers')

p.write_text(t, encoding='utf-8')

# ---------------------------------------------------------------------------
# Report payload includes configured school shifts
# ---------------------------------------------------------------------------
p = Path('worker/reports.js')
t = p.read_text(encoding='utf-8')

t = replace_once(t, """  const [scanResult, attendanceResult, checkpointResult, guardResult] = await Promise.all([""", """  const [scanResult, attendanceResult, checkpointResult, guardResult, shiftResult] = await Promise.all([""", 'reports promise result')
old = """    env.DB.prepare(
      `SELECT id, nama, no_kad_pengenalan, no_pk, guard_status, jawatan, active
         FROM users
        WHERE department_id = ?
          AND active = 1
          AND LOWER(jawatan) IN ('patrol', 'supervisor')
        ORDER BY CASE WHEN no_pk IS NULL OR no_pk = '' THEN 1 ELSE 0 END,
                 CAST(no_pk AS INTEGER) ASC, nama ASC, id ASC`,
    ).bind(departmentId).all(),
  ]);"""
new = """    env.DB.prepare(
      `SELECT id, nama, no_kad_pengenalan, no_pk, guard_status, jawatan, active
         FROM users
        WHERE department_id = ?
          AND active = 1
          AND LOWER(jawatan) IN ('patrol', 'supervisor')
        ORDER BY CASE WHEN no_pk IS NULL OR no_pk = '' THEN 1 ELSE 0 END,
                 CAST(no_pk AS INTEGER) ASC, nama ASC, id ASC`,
    ).bind(departmentId).all(),
    env.DB.prepare(
      `SELECT shift_number, start_minutes, end_minutes, required_guards
         FROM department_shifts
        WHERE department_id = ? AND active = 1
        ORDER BY shift_number ASC`,
    ).bind(departmentId).all(),
  ]);"""
t = replace_once(t, old, new, 'reports shift query')

t = replace_once(t, """      zone: departmentMeta.zone || '',
      state: 'KEDAH',
    },""", """      zone: departmentMeta.zone || '',
      state: 'KEDAH',
      shifts: (shiftResult.results ?? []).map((row) => ({
        shiftNumber: Number(row.shift_number),
        startMinutes: Number(row.start_minutes),
        endMinutes: Number(row.end_minutes),
        requiredGuards: Number(row.required_guards || 0),
      })),
    },""", 'reports payload shifts')

p.write_text(t, encoding='utf-8')

# ---------------------------------------------------------------------------
# PKK 2: configured contract counts/times + dynamic shift columns
# ---------------------------------------------------------------------------
p = Path('lib/features/admin/pkk_pdf_generator.dart')
t = p.read_text(encoding='utf-8')

# all attendance session calls need department shift config
t = t.replace("_attendanceSessions(\n      data['attendance'] as List<dynamic>? ?? const [],\n    )", "_attendanceSessions(\n      data['attendance'] as List<dynamic>? ?? const [],\n      department,\n    )")

# compiled remove derived counts and change page args
t = replace_once(t, """    final requiredByShift = _requiredGuardsByShift(
      attendanceSessions,
      month,
      year,
    );

""", '', 'pkk compiled remove inferred counts')
t = replace_once(t, """          sessions: attendanceSessions,
          requiredShift1: requiredByShift[1] ?? 0,
          requiredShift2: requiredByShift[2] ?? 0,
""", """          sessions: attendanceSessions,
          shifts: _departmentShifts(department),
""", 'pkk compiled page shifts')

# standalone remove inferred counts + args
t = replace_once(t, """    final requiredByShift = _requiredGuardsByShift(sessions, month, year);
    final doc = pw.Document();""", """    final doc = pw.Document();""", 'pkk standalone remove inferred counts')
t = replace_once(t, """          sessions: sessions,
          requiredShift1: requiredByShift[1] ?? 0,
          requiredShift2: requiredByShift[2] ?? 0,
""", """          sessions: sessions,
          shifts: _departmentShifts(department),
""", 'pkk standalone page shifts')

# pkk2 page signature and summary/block args
t = replace_once(t, """    required List<_GuardMeta> guards,
    required List<_GuardSession> sessions,
    required int requiredShift1,
    required int requiredShift2,
  }) {""", """    required List<_GuardMeta> guards,
    required List<_GuardSession> sessions,
    required List<_ShiftMeta> shifts,
  }) {""", 'pkk page signature')
t = replace_once(t, "        _pkk2ContractSummary(requiredShift1, requiredShift2),", "        _pkk2ContractSummary(shifts),", 'pkk contract summary call')
t = replace_once(t, """            sessions: sessions,
            month: month,
            year: year,
          ),""", """            sessions: sessions,
            shifts: shifts,
            month: month,
            year: year,
          ),""", 'pkk attendance block shift arg')

# replace contract summary function entire opening/body up to return row using regex
pattern = re.compile(r"  static pw\.Widget _pkk2ContractSummary\([\s\S]*?\n  }\n\n  static pw\.Widget _pkk2AttendanceBlock\(\{", re.M)
match = pattern.search(t)
if not match:
    raise SystemExit('pkk contract summary block not found')
contract = '''  static pw.Widget _pkk2ContractSummary(List<_ShiftMeta> shifts) {
    final byNumber = {for (final shift in shifts) shift.number: shift};

    String countValue(int number) {
      final shift = byNumber[number];
      if (shift == null || shift.requiredGuards <= 0) return '';
      return '${shift.requiredGuards}';
    }

    String timeValue(int number) {
      final shift = byNumber[number];
      if (shift == null) return '';
      return 'Jam ${_dotTime(shift.startMinutes)} hingga\\njam ${_dotTime(shift.endMinutes)}';
    }

    pw.Widget shiftCount() => pw.Expanded(
      child: pw.Column(
        children: [
          _boxText(
            '1   BILANGAN PENGAWAL KESELAMATAN YANG DITETAPKAN MENGIKUT SYIF DALAM DOKUMEN PERJANJIAN KONTRAK\\n(Sila nyatakan)',
            fontSize: 5.1,
            bold: true,
            height: 18,
            fill: PdfColors.grey300,
          ),
          pw.Row(
            children: [
              for (var shift = 1; shift <= 3; shift++)
                pw.Expanded(child: _boxText('SYIF $shift', height: 9)),
            ],
          ),
          pw.Row(
            children: [
              for (var shift = 1; shift <= 3; shift++)
                pw.Expanded(child: _boxText(countValue(shift), height: 9)),
            ],
          ),
        ],
      ),
    );

    pw.Widget shiftHours() => pw.Expanded(
      child: pw.Column(
        children: [
          _boxText(
            '2   WAKTU BERTUGAS SETIAP SYIF\\n(Sila nyatakan)',
            fontSize: 5.1,
            bold: true,
            height: 18,
            fill: PdfColors.grey300,
          ),
          pw.Row(
            children: [
              for (var shift = 1; shift <= 3; shift++)
                pw.Expanded(child: _boxText('SYIF $shift', height: 9)),
            ],
          ),
          pw.Row(
            children: [
              for (var shift = 1; shift <= 3; shift++)
                pw.Expanded(child: _boxText(timeValue(shift), height: 13)),
            ],
          ),
        ],
      ),
    );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [shiftCount(), pw.SizedBox(width: 18), shiftHours()],
    );
  }

  static pw.Widget _pkk2AttendanceBlock({'''
t = t[:match.start()] + contract + t[match.end():]

# attendance block signature
t = replace_once(t, """    required List<_GuardMeta> guards,
    required List<_GuardSession> sessions,
    required int month,""", """    required List<_GuardMeta> guards,
    required List<_GuardSession> sessions,
    required List<_ShiftMeta> shifts,
    required int month,""", 'pkk block signature')

# header shift columns and guard daily shift loops
t = replace_once(t, """                    pw.Expanded(
                      child: _boxText(
                        day == null ? '' : 'SYIF 1',
                        height: 11,
                        fontSize: 3.6,
                        fill: PdfColors.grey200,
                      ),
                    ),
                    pw.Expanded(
                      child: _boxText(
                        day == null ? '' : 'SYIF 2',
                        height: 11,
                        fontSize: 3.6,
                        fill: PdfColors.grey200,
                      ),
                    ),
                    pw.Expanded(
                      child: _boxText(
                        day == null ? '' : 'SYIF 3',
                        height: 11,
                        fontSize: 3.6,
                        fill: PdfColors.grey200,
                      ),
                    ),""", """                    for (final shift in shifts)
                      pw.Expanded(
                        child: _boxText(
                          day == null ? '' : 'SYIF ${shift.number}',
                          height: 11,
                          fontSize: 3.6,
                          fill: PdfColors.grey200,
                        ),
                      ),""", 'pkk dynamic header shifts')
t = replace_once(t, """                  for (var shift = 1; shift <= 3; shift++)
                    pw.Expanded(
                      child: _boxText(
                        day == null
                            ? ''
                            : _hoursFor(
                                sessions,
                                guard.id,
                                year,
                                month,
                                day,
                                shift,
                              ),""", """                  for (final shift in shifts)
                    pw.Expanded(
                      child: _boxText(
                        day == null
                            ? ''
                            : _hoursFor(
                                sessions,
                                guard.id,
                                year,
                                month,
                                day,
                                shift.number,
                              ),""", 'pkk dynamic guard shifts')

# replace attendance parser signature and session assignment
old = """  static List<_GuardSession> _attendanceSessions(List<dynamic> raw) {
"""
new = """  static List<_GuardSession> _attendanceSessions(
    List<dynamic> raw,
    Map<String, dynamic> department,
  ) {
    final shifts = _departmentShifts(department);
"""
t = replace_once(t, old, new, 'pkk attendance parser signature')
t = replace_once(t, "result.add(_sessionFromPunch(pendingIn, null));", "result.add(_sessionFromPunch(pendingIn, null, shifts));", 'pkk session dangling replacement 1')
# remaining occurrences (OUT and final pending) should be 2
t = t.replace("result.add(_sessionFromPunch(pendingIn, row));", "result.add(_sessionFromPunch(pendingIn, row, shifts));")
t = t.replace("result.add(_sessionFromPunch(pendingIn, null));", "result.add(_sessionFromPunch(pendingIn, null, shifts));")

# sessionFromPunch signature and shift logic
old = """  static _GuardSession _sessionFromPunch(
    Map<String, dynamic> input,
    Map<String, dynamic>? output,
  ) {
    final start = input['_local'] as DateTime;
    final end = output?['_local'] as DateTime?;
    final shift = start.hour >= 6 && start.hour < 18 ? 1 : 2;
"""
new = """  static _GuardSession _sessionFromPunch(
    Map<String, dynamic> input,
    Map<String, dynamic>? output,
    List<_ShiftMeta> shifts,
  ) {
    final start = input['_local'] as DateTime;
    final end = output?['_local'] as DateTime?;
    final shift = _shiftFor(start, shifts);
"""
t = replace_once(t, old, new, 'pkk session shift assignment')

# remove inferred function and replace with configured shift helpers
pattern = re.compile(r"  static Map<int, int> _requiredGuardsByShift\([\s\S]*?\n  }\n\n  static String _hoursFor", re.M)
match = pattern.search(t)
if not match:
    raise SystemExit('pkk inferred shift function not found')
helpers = '''  static List<_ShiftMeta> _departmentShifts(Map<String, dynamic> department) {
    final raw = department['shifts'] as List<dynamic>? ?? const [];
    final shifts = <_ShiftMeta>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final number = (row['shiftNumber'] as num?)?.toInt() ?? 0;
      final startMinutes = (row['startMinutes'] as num?)?.toInt() ?? -1;
      final endMinutes = (row['endMinutes'] as num?)?.toInt() ?? -1;
      final requiredGuards = (row['requiredGuards'] as num?)?.toInt() ?? 0;
      if (number < 1 || number > 3 ||
          startMinutes < 0 || startMinutes > 1439 ||
          endMinutes < 0 || endMinutes > 1439 ||
          startMinutes == endMinutes) {
        continue;
      }
      shifts.add(_ShiftMeta(
        number: number,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        requiredGuards: requiredGuards,
      ));
    }
    shifts.sort((a, b) => a.number.compareTo(b.number));
    if (shifts.isNotEmpty) return shifts;
    return const <_ShiftMeta>[
      _ShiftMeta(number: 1, startMinutes: 480, endMinutes: 1200, requiredGuards: 0),
      _ShiftMeta(number: 2, startMinutes: 1200, endMinutes: 480, requiredGuards: 0),
    ];
  }

  static int _shiftFor(DateTime start, List<_ShiftMeta> shifts) {
    final minutes = start.hour * 60 + start.minute;
    for (final shift in shifts) {
      final inShift = shift.startMinutes < shift.endMinutes
          ? minutes >= shift.startMinutes && minutes < shift.endMinutes
          : minutes >= shift.startMinutes || minutes < shift.endMinutes;
      if (inShift) return shift.number;
    }
    return shifts.isEmpty ? 1 : shifts.first.number;
  }

  static String _dotTime(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}.${(minutes % 60).toString().padLeft(2, '0')}';

  static String _hoursFor'''
t = t[:match.start()] + helpers + t[match.end():]

# add shift meta class before GuardMeta
shift_meta = '''class _ShiftMeta {
  const _ShiftMeta({
    required this.number,
    required this.startMinutes,
    required this.endMinutes,
    required this.requiredGuards,
  });

  final int number;
  final int startMinutes;
  final int endMinutes;
  final int requiredGuards;
}

'''
t = replace_once(t, 'class _GuardMeta {\n', shift_meta + 'class _GuardMeta {\n', 'pkk shift meta class')

p.write_text(t, encoding='utf-8')

print('School shift structure patches applied.')
