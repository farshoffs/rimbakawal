from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'Anchor not found in {path}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


def insert_before(path: str, anchor: str, block: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if block.strip() in text:
        return
    if anchor not in text:
        raise RuntimeError(f'Insert anchor not found in {path}: {anchor!r}')
    p.write_text(text.replace(anchor, block + '\n' + anchor, 1), encoding='utf-8')


# ---------------------------------------------------------------------------
# Flutter API surface: company-scoped school queries + archive / restore.
# ---------------------------------------------------------------------------
replace_once(
    'lib/core/api/api_service.dart',
    """  Future<List<DepartmentRecord>> getAdminDepartments() async {\n    final data = _decode(\n      await _cachedGet(_uri('/api/admin/departments'), headers: _headers()),\n    );\n    return (data['departments'] as List<dynamic>? ?? const [])\n        .map(\n          (item) =>\n              DepartmentRecord.fromJson(Map<String, dynamic>.from(item as Map)),\n        )\n        .toList();\n  }\n""",
    """  Future<List<DepartmentRecord>> getAdminDepartments({\n    int? companyId,\n    bool includeArchived = false,\n  }) async {\n    final data = _decode(\n      await _cachedGet(\n        _uri('/api/admin/departments', {\n          if (companyId != null) 'companyId': companyId.toString(),\n          if (includeArchived) 'includeArchived': '1',\n        }),\n        headers: _headers(),\n      ),\n    );\n    return (data['departments'] as List<dynamic>? ?? const [])\n        .map(\n          (item) =>\n              DepartmentRecord.fromJson(Map<String, dynamic>.from(item as Map)),\n        )\n        .toList();\n  }\n""",
)

insert_before(
    'lib/core/api/api_service.dart',
    "  Future<List<DepartmentRecord>> getAdminDepartments({\n",
    """  Future<void> deleteCompany(int companyId) async {\n    _decode(\n      await http.delete(\n        _uri('/api/admin/companies/$companyId'),\n        headers: _headers(),\n      ),\n    );\n  }\n\n  Future<void> restoreCompany(int companyId) async {\n    _decode(\n      await http.post(\n        _uri('/api/admin/companies/$companyId/restore'),\n        headers: _headers(),\n      ),\n    );\n  }\n""",
)

insert_before(
    'lib/core/api/api_service.dart',
    "  Future<List<CheckpointRecord>> getAdminCheckpoints(int departmentId) async {\n",
    """  Future<void> restoreDepartment(int departmentId) async {\n    _decode(\n      await http.post(\n        _uri('/api/admin/departments/$departmentId/restore'),\n        headers: _headers(),\n      ),\n    );\n  }\n""",
)

# ---------------------------------------------------------------------------
# Attendance: overnight IN->OUT state machine and school archive/restore.
# ---------------------------------------------------------------------------
replace_once(
    'worker/attendance.js',
    """      if (url.pathname === '/api/admin/departments' && request.method === 'GET') {\n        return adminDepartments(request, env);\n      }\n""",
    """      if (url.pathname === '/api/admin/departments' && request.method === 'GET') {\n        return adminDepartments(request, env, url);\n      }\n""",
)

replace_once(
    'worker/attendance.js',
    """      if (departmentMatch && request.method === 'DELETE') {\n        return deleteDepartment(request, env, Number(departmentMatch[1]));\n      }\n\n      if (url.pathname === '/api/admin/command-center' && request.method === 'GET') {\n""",
    """      if (departmentMatch && request.method === 'DELETE') {\n        return deleteDepartment(request, env, Number(departmentMatch[1]));\n      }\n      const departmentRestoreMatch = url.pathname.match(/^\\/api\\/admin\\/departments\\/(\\d+)\\/restore$/);\n      if (departmentRestoreMatch && request.method === 'POST') {\n        return restoreDepartment(request, env, Number(departmentRestoreMatch[1]));\n      }\n\n      if (url.pathname === '/api/admin/command-center' && request.method === 'GET') {\n""",
)

replace_once(
    'worker/attendance.js',
    """  const workDate = malaysiaDateKey(new Date());\n  const result = await env.DB.prepare(\n    `SELECT id, punch_type, punched_at, latitude, longitude, accuracy_m, distance_m,\n            face_status, face_score, face_model, face_reason\n     FROM attendance_records\n     WHERE user_id = ? AND work_date = ?\n     ORDER BY punched_at ASC, id ASC`,\n  ).bind(auth.user.id, workDate).all();\n  const records = (result.results ?? []).map(attendanceJson);\n  const latest = records.length ? records[records.length - 1] : null;\n\n  return json({\n    workDate,\n    department: departmentJson(department),\n    nextPunchType: latest?.punchType === 'IN' ? 'OUT' : 'IN',\n    latest,\n    records,\n    profilePictureConfigured: Boolean(auth.user.profile_picture),\n  });\n""",
    """  const todayWorkDate = malaysiaDateKey(new Date());\n  const latestGlobal = await env.DB.prepare(\n    `SELECT id, work_date, punch_type, punched_at\n       FROM attendance_records\n      WHERE user_id = ?\n      ORDER BY punched_at DESC, id DESC\n      LIMIT 1`,\n  ).bind(auth.user.id).first();\n  const hasOpenShift = latestGlobal?.punch_type === 'IN';\n  const workDate = hasOpenShift ? String(latestGlobal.work_date) : todayWorkDate;\n  const result = await env.DB.prepare(\n    `SELECT id, punch_type, punched_at, latitude, longitude, accuracy_m, distance_m,\n            face_status, face_score, face_model, face_reason\n     FROM attendance_records\n     WHERE user_id = ? AND work_date = ?\n     ORDER BY punched_at ASC, id ASC`,\n  ).bind(auth.user.id, workDate).all();\n  const records = (result.results ?? []).map(attendanceJson);\n  const latest = records.length ? records[records.length - 1] : null;\n\n  return json({\n    workDate,\n    currentDate: todayWorkDate,\n    openShiftFromPreviousDate: hasOpenShift && workDate !== todayWorkDate,\n    department: departmentJson(department),\n    nextPunchType: hasOpenShift ? 'OUT' : 'IN',\n    latest,\n    records,\n    profilePictureConfigured: Boolean(auth.user.profile_picture),\n  });\n""",
)

replace_once(
    'worker/attendance.js',
    """  const workDate = malaysiaDateKey(new Date());\n  const latest = await env.DB.prepare(\n    `SELECT id, punch_type, punched_at\n     FROM attendance_records\n     WHERE user_id = ? AND work_date = ?\n     ORDER BY punched_at DESC, id DESC LIMIT 1`,\n  ).bind(auth.user.id, workDate).first();\n  if (latest && Date.now() - Date.parse(latest.punched_at) < 60000) {\n    return json({ error: 'Punch terlalu rapat. Tunggu sekurang-kurangnya 1 minit.' }, 429);\n  }\n  const punchType = latest?.punch_type === 'IN' ? 'OUT' : 'IN';\n""",
    """  const todayWorkDate = malaysiaDateKey(new Date());\n  const latest = await env.DB.prepare(\n    `SELECT id, work_date, punch_type, punched_at\n       FROM attendance_records\n      WHERE user_id = ?\n      ORDER BY punched_at DESC, id DESC\n      LIMIT 1`,\n  ).bind(auth.user.id).first();\n  if (latest && Date.now() - Date.parse(latest.punched_at) < 60000) {\n    return json({ error: 'Punch terlalu rapat. Tunggu sekurang-kurangnya 1 minit.' }, 429);\n  }\n  const punchType = latest?.punch_type === 'IN' ? 'OUT' : 'IN';\n  // OUT belongs to the same work/shift date as its preceding IN even when the\n  // calendar has crossed midnight (for example 20:00 -> 08:00).\n  const workDate = punchType === 'OUT' && latest?.work_date\n    ? String(latest.work_date)\n    : todayWorkDate;\n""",
)

old_admin_departments = """async function adminDepartments(request, env) {\n  const auth = await requireReportAccess(request, env);\n  if (auth.response) return auth.response;\n  const role = String(auth.user.jawatan || '').trim().toLowerCase();\n  const scopeCompanyId = role === 'administration'\n    ? Number(auth.user.company_id || 0) || null\n    : null;\n  if (role === 'administration' && !scopeCompanyId) {\n    return json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Syarikat.' }, 409);\n  }\n\n  const sql = `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,\n            d.attendance_latitude, d.attendance_longitude, d.attendance_radius_m,\n            d.attendance_location_label, d.company_id,\n            COALESCE(co.name, d.company_name, '') AS company_name, d.zone,\n            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count\n     FROM departments d\n     LEFT JOIN companies co ON co.id = d.company_id\n     LEFT JOIN checkpoints c ON c.department_id = d.id\n     WHERE d.active = 1 ${scopeCompanyId ? 'AND d.company_id = ?' : ''}\n     GROUP BY d.id\n     ORDER BY d.name ASC`;\n  const result = scopeCompanyId\n    ? await env.DB.prepare(sql).bind(scopeCompanyId).all()\n    : await env.DB.prepare(sql).all();\n  return json({ departments: (result.results ?? []).map(departmentJson) });\n}\n"""
new_admin_departments = """async function adminDepartments(request, env, url) {\n  const auth = await requireReportAccess(request, env);\n  if (auth.response) return auth.response;\n  const role = String(auth.user.jawatan || '').trim().toLowerCase();\n  const ownCompanyId = Number(auth.user.company_id || 0) || null;\n  const requestedCompanyId = Number(url.searchParams.get('companyId') || 0) || null;\n  const scopeCompanyId = role === 'administration' ? ownCompanyId : requestedCompanyId;\n  if (role === 'administration' && !scopeCompanyId) {\n    return json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Syarikat.' }, 409);\n  }\n  const includeArchived = role === 'management' && url.searchParams.get('includeArchived') === '1';\n\n  const where = [includeArchived ? '1 = 1' : 'd.active = 1'];\n  const binds = [];\n  if (scopeCompanyId) {\n    where.push('d.company_id = ?');\n    binds.push(scopeCompanyId);\n  }\n  const sql = `SELECT d.id, d.name, d.session_interval_minutes, d.session_start_minutes, d.active,\n            d.attendance_latitude, d.attendance_longitude, d.attendance_radius_m,\n            d.attendance_location_label, d.company_id,\n            COALESCE(co.name, d.company_name, '') AS company_name, d.zone,\n            COUNT(CASE WHEN c.active = 1 THEN 1 END) AS checkpoint_count\n     FROM departments d\n     LEFT JOIN companies co ON co.id = d.company_id\n     LEFT JOIN checkpoints c ON c.department_id = d.id\n     WHERE ${where.join(' AND ')}\n     GROUP BY d.id\n     ORDER BY d.active DESC, company_name COLLATE NOCASE ASC, d.name COLLATE NOCASE ASC`;\n  const result = await env.DB.prepare(sql).bind(...binds).all();\n  return json({ departments: (result.results ?? []).map(departmentJson) });\n}\n"""
replace_once('worker/attendance.js', old_admin_departments, new_admin_departments)

old_delete_department = """async function deleteDepartment(request, env, departmentId) {\n  const auth = await requireManagement(request, env);\n  if (auth.response) return auth.response;\n  if (!Number.isInteger(departmentId) || departmentId <= 0) {\n    return json({ error: 'Sekolah tidak sah.' }, 400);\n  }\n  const existing = await getDepartment(env, departmentId);\n  if (!existing) return json({ error: 'Sekolah tidak ditemui.' }, 404);\n\n  const assigned = await env.DB.prepare(\n    'SELECT COUNT(*) AS total FROM users WHERE department_id = ? AND active = 1',\n  ).bind(departmentId).first();\n  if (Number(assigned?.total || 0) > 0) {\n    return json({\n      error: 'Pindahkan atau nyahaktifkan semua pengguna aktif sekolah ini sebelum memadam sekolah.',\n    }, 409);\n  }\n\n  await env.DB.batch([\n    env.DB.prepare(\n      'UPDATE departments SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?',\n    ).bind(departmentId),\n    env.DB.prepare(\n      'UPDATE checkpoints SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE department_id = ?',\n    ).bind(departmentId),\n  ]);\n  return json({ ok: true, deleted: true });\n}\n"""
new_delete_department = """async function deleteDepartment(request, env, departmentId) {\n  const auth = await requireManagement(request, env);\n  if (auth.response) return auth.response;\n  if (!Number.isInteger(departmentId) || departmentId <= 0) {\n    return json({ error: 'Sekolah tidak sah.' }, 400);\n  }\n  const existing = await getDepartment(env, departmentId);\n  if (!existing) return json({ error: 'Sekolah tidak ditemui.' }, 404);\n  if (Number(existing.active) !== 1) {\n    return json({ ok: true, archived: true, alreadyArchived: true });\n  }\n\n  const [checkpoints, users] = await Promise.all([\n    env.DB.prepare('SELECT id, active FROM checkpoints WHERE department_id = ? ORDER BY id').bind(departmentId).all(),\n    env.DB.prepare('SELECT id, active FROM users WHERE department_id = ? ORDER BY id').bind(departmentId).all(),\n  ]);\n  const snapshot = JSON.stringify({\n    department: { id: departmentId, active: Number(existing.active) },\n    checkpoints: (checkpoints.results ?? []).map((row) => ({ id: Number(row.id), active: Number(row.active) })),\n    users: (users.results ?? []).map((row) => ({ id: Number(row.id), active: Number(row.active) })),\n  });\n  await env.DB.batch([\n    env.DB.prepare(\n      `INSERT INTO entity_archives (entity_type, entity_id, snapshot_json, archived_by)\n       VALUES ('department', ?, ?, ?)`,\n    ).bind(departmentId, snapshot, auth.user.id),\n    env.DB.prepare(\n      'UPDATE departments SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?',\n    ).bind(departmentId),\n    env.DB.prepare(\n      'UPDATE checkpoints SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE department_id = ?',\n    ).bind(departmentId),\n    env.DB.prepare(\n      'UPDATE users SET active = 0 WHERE department_id = ?',\n    ).bind(departmentId),\n  ]);\n  return json({ ok: true, archived: true, undoAvailable: true });\n}\n\nasync function restoreDepartment(request, env, departmentId) {\n  const auth = await requireManagement(request, env);\n  if (auth.response) return auth.response;\n  const archive = await env.DB.prepare(\n    `SELECT id, snapshot_json\n       FROM entity_archives\n      WHERE entity_type = 'department' AND entity_id = ? AND restored_at IS NULL\n      ORDER BY id DESC LIMIT 1`,\n  ).bind(departmentId).first();\n  if (!archive) {\n    return json({ error: 'Tiada rekod arkib Sekolah yang boleh dipulihkan.' }, 409);\n  }\n  let snapshot;\n  try { snapshot = JSON.parse(archive.snapshot_json); } catch (_) {\n    return json({ error: 'Snapshot arkib Sekolah rosak.' }, 500);\n  }\n  const statements = [\n    env.DB.prepare('UPDATE departments SET active = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')\n      .bind(Number(snapshot?.department?.active ?? 1), departmentId),\n  ];\n  for (const row of snapshot?.checkpoints ?? []) {\n    statements.push(env.DB.prepare('UPDATE checkpoints SET active = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')\n      .bind(Number(row.active ?? 0), Number(row.id)));\n  }\n  for (const row of snapshot?.users ?? []) {\n    statements.push(env.DB.prepare('UPDATE users SET active = ? WHERE id = ?')\n      .bind(Number(row.active ?? 0), Number(row.id)));\n  }\n  statements.push(\n    env.DB.prepare('UPDATE entity_archives SET restored_at = CURRENT_TIMESTAMP, restored_by = ? WHERE id = ?')\n      .bind(auth.user.id, Number(archive.id)),\n  );\n  await env.DB.batch(statements);\n  return json({ ok: true, restored: true });\n}\n"""
replace_once('worker/attendance.js', old_delete_department, new_delete_department)

# ---------------------------------------------------------------------------
# Company archive/restore endpoints with exact child-state snapshots.
# ---------------------------------------------------------------------------
replace_once(
    'worker/company_management.js',
    """      if (companyMatch && request.method === 'PUT') {\n        return updateCompany(request, env, Number(companyMatch[1]));\n      }\n\n      if (url.pathname === '/api/admin/users' && request.method === 'POST') {\n""",
    """      if (companyMatch && request.method === 'PUT') {\n        return updateCompany(request, env, Number(companyMatch[1]));\n      }\n      if (companyMatch && request.method === 'DELETE') {\n        return archiveCompany(request, env, Number(companyMatch[1]));\n      }\n      const companyRestoreMatch = url.pathname.match(/^\\/api\\/admin\\/companies\\/(\\d+)\\/restore$/);\n      if (companyRestoreMatch && request.method === 'POST') {\n        return restoreCompany(request, env, Number(companyRestoreMatch[1]));\n      }\n\n      if (url.pathname === '/api/admin/users' && request.method === 'POST') {\n""",
)

insert_before(
    'worker/company_management.js',
    'async function resolveCompanyPayload(env, original) {',
    """async function archiveCompany(request, env, companyId) {\n  const auth = await requireManagement(request, env);\n  if (auth.response) return auth.response;\n  if (!Number.isInteger(companyId) || companyId <= 0) {\n    return json({ error: 'Syarikat tidak sah.' }, 400);\n  }\n  const company = await getCompany(env, companyId);\n  if (!company) return json({ error: 'Syarikat tidak ditemui.' }, 404);\n  if (Number(company.active) !== 1) {\n    return json({ ok: true, archived: true, alreadyArchived: true });\n  }\n\n  const [departments, checkpoints, users] = await Promise.all([\n    env.DB.prepare('SELECT id, active FROM departments WHERE company_id = ? ORDER BY id').bind(companyId).all(),\n    env.DB.prepare(`SELECT c.id, c.active\n                      FROM checkpoints c\n                      JOIN departments d ON d.id = c.department_id\n                     WHERE d.company_id = ? ORDER BY c.id`).bind(companyId).all(),\n    env.DB.prepare('SELECT id, active FROM users WHERE company_id = ? ORDER BY id').bind(companyId).all(),\n  ]);\n  const snapshot = JSON.stringify({\n    company: { id: companyId, active: Number(company.active) },\n    departments: (departments.results ?? []).map((row) => ({ id: Number(row.id), active: Number(row.active) })),\n    checkpoints: (checkpoints.results ?? []).map((row) => ({ id: Number(row.id), active: Number(row.active) })),\n    users: (users.results ?? []).map((row) => ({ id: Number(row.id), active: Number(row.active) })),\n  });\n\n  await env.DB.batch([\n    env.DB.prepare(\n      `INSERT INTO entity_archives (entity_type, entity_id, snapshot_json, archived_by)\n       VALUES ('company', ?, ?, ?)`,\n    ).bind(companyId, snapshot, auth.user.id),\n    env.DB.prepare('UPDATE companies SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?').bind(companyId),\n    env.DB.prepare('UPDATE departments SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE company_id = ?').bind(companyId),\n    env.DB.prepare(`UPDATE checkpoints\n                       SET active = 0, updated_at = CURRENT_TIMESTAMP\n                     WHERE department_id IN (SELECT id FROM departments WHERE company_id = ?)`).bind(companyId),\n    env.DB.prepare('UPDATE users SET active = 0 WHERE company_id = ?').bind(companyId),\n  ]);\n  return json({ ok: true, archived: true, undoAvailable: true });\n}\n\nasync function restoreCompany(request, env, companyId) {\n  const auth = await requireManagement(request, env);\n  if (auth.response) return auth.response;\n  const archive = await env.DB.prepare(\n    `SELECT id, snapshot_json\n       FROM entity_archives\n      WHERE entity_type = 'company' AND entity_id = ? AND restored_at IS NULL\n      ORDER BY id DESC LIMIT 1`,\n  ).bind(companyId).first();\n  if (!archive) {\n    return json({ error: 'Tiada rekod arkib Syarikat yang boleh dipulihkan.' }, 409);\n  }\n  let snapshot;\n  try { snapshot = JSON.parse(archive.snapshot_json); } catch (_) {\n    return json({ error: 'Snapshot arkib Syarikat rosak.' }, 500);\n  }\n  const statements = [\n    env.DB.prepare('UPDATE companies SET active = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')\n      .bind(Number(snapshot?.company?.active ?? 1), companyId),\n  ];\n  for (const row of snapshot?.departments ?? []) {\n    statements.push(env.DB.prepare('UPDATE departments SET active = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')\n      .bind(Number(row.active ?? 0), Number(row.id)));\n  }\n  for (const row of snapshot?.checkpoints ?? []) {\n    statements.push(env.DB.prepare('UPDATE checkpoints SET active = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')\n      .bind(Number(row.active ?? 0), Number(row.id)));\n  }\n  for (const row of snapshot?.users ?? []) {\n    statements.push(env.DB.prepare('UPDATE users SET active = ? WHERE id = ?')\n      .bind(Number(row.active ?? 0), Number(row.id)));\n  }\n  statements.push(\n    env.DB.prepare('UPDATE entity_archives SET restored_at = CURRENT_TIMESTAMP, restored_by = ? WHERE id = ?')\n      .bind(auth.user.id, Number(archive.id)),\n  );\n  await env.DB.batch(statements);\n  return json({ ok: true, restored: true });\n}\n""",
)

# ---------------------------------------------------------------------------
# Reports: make the school scope explicit and safe for Company Administration.
# Avoid delegating report generation through monitor-only command-center auth.
# ---------------------------------------------------------------------------
reports = r'''import commandCenterWorker from './command_center_period.js';

const SESSION_COOKIE = 'rk_session';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const reportOnlyAllowed =
      (url.pathname === '/api/auth/session' && request.method === 'GET') ||
      (url.pathname === '/api/auth/logout' && request.method === 'POST') ||
      (url.pathname === '/api/admin/reports' && request.method === 'GET') ||
      (url.pathname === '/api/admin/departments' && request.method === 'GET');
    if (url.pathname.startsWith('/api/') &&
        url.pathname !== '/api/auth/login' &&
        !reportOnlyAllowed) {
      const denied = await denyAdministrationOperationalAccess(request, env);
      if (denied) return denied;
    }
    if (url.pathname === '/api/admin/reports' && request.method === 'GET') {
      return monthlyReport(request, env, url);
    }
    return commandCenterWorker.fetch(request, env, ctx);
  },
  async scheduled(event, env, ctx) {
    if (typeof commandCenterWorker.scheduled === 'function') {
      return commandCenterWorker.scheduled(event, env, ctx);
    }
  },
};

async function monthlyReport(request, env, url) {
  const auth = await requireReportAccess(request, env);
  if (auth.response) return auth.response;

  const from = String(url.searchParams.get('from') || '');
  const to = String(url.searchParams.get('to') || '');
  const departmentId = Number(url.searchParams.get('departmentId') || 0);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to) || from > to) {
    return json({ error: 'Tarikh laporan tidak sah.' }, 400);
  }
  if (!Number.isInteger(departmentId) || departmentId <= 0) {
    return json({ error: 'Pilih satu Sekolah untuk laporan PKK.' }, 400);
  }

  const departmentMeta = await env.DB.prepare(
    `SELECT d.id, d.name, d.active, d.company_id,
            COALESCE(c.name, d.company_name, '') AS company_name, d.zone
       FROM departments d
       LEFT JOIN companies c ON c.id = d.company_id
      WHERE d.id = ? LIMIT 1`,
  ).bind(departmentId).first();
  if (!departmentMeta) return json({ error: 'Sekolah tidak ditemui.' }, 404);

  const role = String(auth.user.jawatan || '').trim().toLowerCase();
  if (role === 'administration') {
    const ownCompanyId = Number(auth.user.company_id || 0);
    if (!ownCompanyId || Number(departmentMeta.company_id || 0) !== ownCompanyId) {
      return json({ error: 'Sekolah ini bukan di bawah Syarikat akaun anda.' }, 403);
    }
  }

  const fromStart = malaysiaStartIso(from);
  const toEnd = malaysiaEndIso(to);
  const attendanceToEnd = addUtcDays(toEnd, 1);
  if (!fromStart || !toEnd || !attendanceToEnd) {
    return json({ error: 'Tarikh laporan tidak sah.' }, 400);
  }

  const scanSql = `SELECT s.id, s.user_id, s.checkpoint_id, s.scanned_at, s.nfc_uid, s.session_index,
              u.nama, u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan,
              COALESCE(d.name, u.jabatan) AS jabatan,
              COALESCE(c.name, 'Checkpoint') AS checkpoint_name,
              c.position AS checkpoint_position
       FROM nfc_scans s
       JOIN users u ON u.id = s.user_id
       LEFT JOIN departments d ON d.id = u.department_id
       LEFT JOIN checkpoints c ON c.id = s.checkpoint_id
       WHERE s.scanned_at >= ? AND s.scanned_at < ?
         AND u.department_id = ?
       ORDER BY s.scanned_at ASC, s.session_index ASC, c.position ASC, s.id ASC`;

  // Include one extra Malaysian calendar day so a night-shift IN on the
  // last report date can be paired with its OUT on the following morning.
  const attendanceSql = `SELECT a.id, a.user_id, a.department_id, a.work_date,
              a.punch_type, a.punched_at, a.latitude, a.longitude, a.distance_m,
              a.face_status, a.face_score,
              u.nama, u.no_kad_pengenalan, u.no_pk, u.guard_status, u.jawatan,
              COALESCE(d.name, u.jabatan) AS jabatan
       FROM attendance_records a
       JOIN users u ON u.id = a.user_id
       LEFT JOIN departments d ON d.id = a.department_id
       WHERE a.punched_at >= ? AND a.punched_at < ?
         AND a.department_id = ?
       ORDER BY a.user_id ASC, a.punched_at ASC, a.id ASC`;

  const [scanResult, attendanceResult, checkpointResult, guardResult] = await Promise.all([
    env.DB.prepare(scanSql).bind(fromStart, toEnd, departmentId).all(),
    env.DB.prepare(attendanceSql).bind(fromStart, attendanceToEnd, departmentId).all(),
    env.DB.prepare(
      `SELECT id, name, position, nfc_uid, active
         FROM checkpoints
        WHERE department_id = ? AND active = 1
        ORDER BY position ASC, id ASC`,
    ).bind(departmentId).all(),
    env.DB.prepare(
      `SELECT id, nama, no_kad_pengenalan, no_pk, guard_status, jawatan, active
         FROM users
        WHERE department_id = ?
          AND active = 1
          AND LOWER(jawatan) IN ('patrol', 'supervisor')
        ORDER BY CASE WHEN no_pk IS NULL OR no_pk = '' THEN 1 ELSE 0 END,
                 CAST(no_pk AS INTEGER) ASC, nama ASC, id ASC`,
    ).bind(departmentId).all(),
  ]);

  const scans = scanResult.results ?? [];
  const attendance = attendanceResult.results ?? [];
  const checkpoints = (checkpointResult.results ?? []).map((row) => ({
    id: Number(row.id),
    name: row.name,
    position: Number(row.position || 0),
    nfcUid: row.nfc_uid || '',
    active: Number(row.active) === 1,
  }));
  const guards = (guardResult.results ?? []).map((row) => ({
    id: Number(row.id),
    nama: row.nama,
    no_kad_pengenalan: row.no_kad_pengenalan || '',
    no_pk: row.no_pk || '',
    guard_status: row.guard_status || 'Tetap',
    jawatan: row.jawatan || 'patrol',
    active: Number(row.active) === 1,
  }));

  return json({
    from,
    to,
    department: {
      id: Number(departmentMeta.id),
      name: departmentMeta.name,
      companyId: departmentMeta.company_id == null ? null : Number(departmentMeta.company_id),
      companyName: departmentMeta.company_name || '',
      zone: departmentMeta.zone || '',
      state: 'KEDAH',
    },
    scans,
    attendance,
    checkpoints,
    guards,
    summary: {
      totalScans: scans.length,
      attendancePunches: attendance.length,
      activeCheckpoints: checkpoints.length,
      activeGuards: guards.length,
    },
  });
}

async function requireReportAccess(request, env) {
  const token = getSessionToken(request);
  if (!token) return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };
  const user = await env.DB.prepare(
    `SELECT u.id, u.jawatan, u.company_id
       FROM sessions s
       JOIN users u ON u.id = s.user_id
      WHERE s.token_hash = ? AND s.expires_at_ms > ? AND u.active = 1
      LIMIT 1`,
  ).bind(await sha256(token), Date.now()).first();
  if (!user) return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  const role = String(user.jawatan || '').trim().toLowerCase();
  if (role !== 'management' && role !== 'administration') {
    return { response: json({ error: 'Akses laporan hanya untuk Admin Sistem atau Pentadbiran Syarikat.' }, 403) };
  }
  if (role === 'administration' && !Number(user.company_id || 0)) {
    return { response: json({ error: 'Pentadbiran Syarikat belum dipautkan kepada Syarikat.' }, 409) };
  }
  return { user };
}

function malaysiaStartIso(dateKey) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) return null;
  const value = new Date(`${dateKey}T00:00:00+08:00`);
  return Number.isNaN(value.getTime()) ? null : value.toISOString();
}

function malaysiaEndIso(dateKey) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) return null;
  const value = new Date(`${dateKey}T00:00:00+08:00`);
  if (Number.isNaN(value.getTime())) return null;
  value.setUTCDate(value.getUTCDate() + 1);
  return value.toISOString();
}

function addUtcDays(iso, days) {
  if (!iso) return null;
  const value = new Date(iso);
  if (Number.isNaN(value.getTime())) return null;
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString();
}

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

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}
'''
Path('worker/reports.js').write_text(reports, encoding='utf-8')

# ---------------------------------------------------------------------------
# Migration for reversible archives. Historical operational data is never
# deleted; the archive stores exact active states for safe undo/restore.
# ---------------------------------------------------------------------------
migration = '''CREATE TABLE IF NOT EXISTS entity_archives (\n  id INTEGER PRIMARY KEY AUTOINCREMENT,\n  entity_type TEXT NOT NULL CHECK(entity_type IN ('company', 'department')),\n  entity_id INTEGER NOT NULL,\n  snapshot_json TEXT NOT NULL,\n  archived_by INTEGER,\n  archived_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,\n  restored_at TEXT,\n  restored_by INTEGER\n);\n\nCREATE INDEX IF NOT EXISTS idx_entity_archives_lookup\n  ON entity_archives(entity_type, entity_id, restored_at, id);\n'''
Path('migrations/0021_entity_archives.sql').write_text(migration, encoding='utf-8')

print('Applied reversible archive, company scope, report access, and overnight attendance fixes.')
