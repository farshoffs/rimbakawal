from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def write(path, text):
    (ROOT / path).write_text(text, encoding='utf-8')


def replace_once(path, old, new, label):
    text = read(path)
    if new in text and old not in text:
        return
    if old not in text:
        raise SystemExit(f'{label}: marker not found in {path}')
    write(path, text.replace(old, new, 1))


def replace_all_text(path, old, new):
    text = read(path)
    if old in text:
        write(path, text.replace(old, new))


# ---------------------------------------------------------------------------
# 1) User-facing terminology: this product is school-only.
# Keep technical field names such as department_id / jabatan untouched.
# ---------------------------------------------------------------------------
for dart_file in (ROOT / 'lib').rglob('*.dart'):
    text = dart_file.read_text(encoding='utf-8')
    if 'Jabatan' in text:
        dart_file.write_text(text.replace('Jabatan', 'Sekolah'), encoding='utf-8')

for js_file in (ROOT / 'worker').glob('*.js'):
    text = js_file.read_text(encoding='utf-8')
    if 'Jabatan' in text:
        js_file.write_text(text.replace('Jabatan', 'Sekolah'), encoding='utf-8')

replace_all_text('README.md', 'Jabatan', 'Sekolah')


# ---------------------------------------------------------------------------
# 2) Patrol: allow any active checkpoint to be scanned in any order.
# Duplicate protection remains in place.
# ---------------------------------------------------------------------------
patrol_path = 'lib/features/patrol/patrol_screen.dart'
patrol = read(patrol_path)
order_block = """      if (bootstrap.routeOrderEnforced) {
        final next = bootstrap.checkpoints
            .where((item) => !completedIds.contains(item.id))
            .firstOrNull;
        if (next != null && next.id != checkpoint.id) {
          throw ApiException('Checkpoint seterusnya ialah ${next.name}.');
        }
      }
"""
if order_block in patrol:
    patrol = patrol.replace(
        order_block,
        "      // Checkpoint boleh direkod dalam apa-apa susunan; perlindungan duplikasi kekal aktif.\n",
        1,
    )
write(patrol_path, patrol)

# Offline bootstrap must advertise flexible routing, and sync must accept it.
offline_path = 'worker/offline.js'
offline = read(offline_path)
offline = offline.replace(
    'routeOrderEnforced: Boolean(department.route_order_enforced),',
    'routeOrderEnforced: false,',
)
offline_order = re.compile(
    r"\n  if \(Boolean\(department\.route_order_enforced\)\) \{\n"
    r"    const routeResult = await env\.DB\.prepare\([\s\S]*?\n  \}\n\n"
    r"  const insert = await env\.DB\.prepare\(",
    re.MULTILINE,
)
offline, count = offline_order.subn(
    "\n  // Flexible route: accept any unscanned active checkpoint in this session.\n\n"
    "  const insert = await env.DB.prepare(",
    offline,
    count=1,
)
if count == 0 and 'Flexible route: accept any unscanned active checkpoint' not in offline:
    raise SystemExit('offline route-order block not found')
write(offline_path, offline)

# Smart online scan uses the same flexible rule.
app_path = 'worker/app.js'
app = read(app_path)
app = app.replace(
    'routeOrderEnforced: Boolean(department.route_order_enforced),',
    'routeOrderEnforced: false,',
)
app_order = re.compile(
    r"\n  if \(Boolean\(department\.route_order_enforced\)\) \{\n"
    r"    const expected = activeCheckpoints\.find\([\s\S]*?\n  \}\n\n"
    r"  const result = await env\.DB\.prepare\(",
    re.MULTILINE,
)
app, count = app_order.subn(
    "\n  // Flexible route: any remaining active checkpoint may be scanned next.\n\n"
    "  const result = await env.DB.prepare(",
    app,
    count=1,
)
if count == 0 and 'Flexible route: any remaining active checkpoint' not in app:
    raise SystemExit('smart scan route-order block not found')
old_next = """  const next = activeCheckpoints.find((row) =>
    Number(row.id) !== Number(checkpoint.id) &&
    !scannedIds.has(Number(row.id)) &&
    Number(row.position) > Number(checkpoint.position)
  ) ?? null;
"""
new_next = """  const next = activeCheckpoints.find((row) =>
    Number(row.id) !== Number(checkpoint.id) &&
    !scannedIds.has(Number(row.id))
  ) ?? null;
"""
if old_next in app:
    app = app.replace(old_next, new_next, 1)
write(app_path, app)


# ---------------------------------------------------------------------------
# 3) API client: delete school/checkpoint endpoints.
# ---------------------------------------------------------------------------
api_path = 'lib/core/api/api_service.dart'
api = read(api_path)
if 'Future<void> deleteDepartment(int departmentId)' not in api:
    marker = """  Future<List<CheckpointRecord>> getAdminCheckpoints(int departmentId) async {
"""
    insert = """  Future<void> deleteDepartment(int departmentId) async {
    _decode(
      await http.delete(
        _uri('/api/admin/departments/$departmentId'),
        headers: _headers(),
      ),
    );
  }

"""
    if marker not in api:
        raise SystemExit('api deleteDepartment insertion marker missing')
    api = api.replace(marker, insert + marker, 1)

if 'Future<void> deleteCheckpoint(int checkpointId)' not in api:
    marker = """  Future<AppUser> updateAdminUser({
"""
    insert = """  Future<void> deleteCheckpoint(int checkpointId) async {
    _decode(
      await http.delete(
        _uri('/api/admin/checkpoints/$checkpointId'),
        headers: _headers(),
      ),
    );
  }

"""
    if marker not in api:
        raise SystemExit('api deleteCheckpoint insertion marker missing')
    api = api.replace(marker, insert + marker, 1)
write(api_path, api)


# ---------------------------------------------------------------------------
# 4) Backend: school deletion in attendance worker (the deployed chain handles
# department administration here). Deleted entities are archived (active=0)
# so historical patrol/attendance/report references stay intact.
# ---------------------------------------------------------------------------
attendance_path = 'worker/attendance.js'
attendance = read(attendance_path)
route_old = """      if (departmentMatch && request.method === 'PUT') {
        return updateDepartment(request, env, Number(departmentMatch[1]));
      }
"""
route_new = """      if (departmentMatch && request.method === 'PUT') {
        return updateDepartment(request, env, Number(departmentMatch[1]));
      }
      if (departmentMatch && request.method === 'DELETE') {
        return deleteDepartment(request, env, Number(departmentMatch[1]));
      }
"""
if route_old in attendance and "request.method === 'DELETE') {\n        return deleteDepartment" not in attendance:
    attendance = attendance.replace(route_old, route_new, 1)

attendance = attendance.replace(
    "LEFT JOIN checkpoints c ON c.department_id = d.id\n     GROUP BY d.id",
    "LEFT JOIN checkpoints c ON c.department_id = d.id\n     WHERE d.active = 1\n     GROUP BY d.id",
    1,
)
attendance = attendance.replace(
    "'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) LIMIT 1'",
    "'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND active = 1 LIMIT 1'",
)
attendance = attendance.replace(
    "'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND id <> ? LIMIT 1'",
    "'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND id <> ? AND active = 1 LIMIT 1'",
)

if 'async function deleteDepartment(request, env, departmentId)' not in attendance:
    marker = """function validateDepartmentBody(body) {
"""
    function_text = """async function deleteDepartment(request, env, departmentId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  if (!Number.isInteger(departmentId) || departmentId <= 0) {
    return json({ error: 'Sekolah tidak sah.' }, 400);
  }
  const existing = await getDepartment(env, departmentId);
  if (!existing) return json({ error: 'Sekolah tidak ditemui.' }, 404);

  const assigned = await env.DB.prepare(
    'SELECT COUNT(*) AS total FROM users WHERE department_id = ? AND active = 1',
  ).bind(departmentId).first();
  if (Number(assigned?.total || 0) > 0) {
    return json({
      error: 'Pindahkan atau nyahaktifkan semua pengguna aktif sekolah ini sebelum memadam sekolah.',
    }, 409);
  }

  await env.DB.batch([
    env.DB.prepare(
      'UPDATE departments SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
    ).bind(departmentId),
    env.DB.prepare(
      'UPDATE checkpoints SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE department_id = ?',
    ).bind(departmentId),
  ]);
  return json({ ok: true, deleted: true });
}

"""
    if marker not in attendance:
        raise SystemExit('attendance deleteDepartment insertion marker missing')
    attendance = attendance.replace(marker, function_text + marker, 1)
write(attendance_path, attendance)


# ---------------------------------------------------------------------------
# 5) Base worker: matching DELETE routes and checkpoint archive/delete support.
# Also keep fallback admin lists aligned with the deployed attendance layer.
# ---------------------------------------------------------------------------
index_path = 'worker/index.js'
index = read(index_path)
old = """      let match = url.pathname.match(/^\\/api\\/admin\\/departments\\/(\\d+)$/);
      if (match && request.method === 'PUT') {
        return updateDepartment(request, env, Number(match[1]));
      }

      match = url.pathname.match(/^\\/api\\/admin\\/checkpoints\\/(\\d+)$/);
      if (match && request.method === 'PUT') {
        return updateCheckpoint(request, env, Number(match[1]));
      }
"""
new = """      let match = url.pathname.match(/^\\/api\\/admin\\/departments\\/(\\d+)$/);
      if (match && request.method === 'PUT') {
        return updateDepartment(request, env, Number(match[1]));
      }
      if (match && request.method === 'DELETE') {
        return deleteDepartment(request, env, Number(match[1]));
      }

      match = url.pathname.match(/^\\/api\\/admin\\/checkpoints\\/(\\d+)$/);
      if (match && request.method === 'PUT') {
        return updateCheckpoint(request, env, Number(match[1]));
      }
      if (match && request.method === 'DELETE') {
        return deleteCheckpoint(request, env, Number(match[1]));
      }
"""
if old in index:
    index = index.replace(old, new, 1)

index = index.replace(
    "LEFT JOIN checkpoints c ON c.department_id = d.id\n     GROUP BY d.id",
    "LEFT JOIN checkpoints c ON c.department_id = d.id\n     WHERE d.active = 1\n     GROUP BY d.id",
    1,
)
index = index.replace(
    "WHERE department_id = ?\n     ORDER BY position ASC, id ASC",
    "WHERE department_id = ? AND active = 1\n     ORDER BY position ASC, id ASC",
    1,
)
index = index.replace(
    "'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) LIMIT 1'",
    "'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND active = 1 LIMIT 1'",
)
index = index.replace(
    "'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND id <> ? LIMIT 1'",
    "'SELECT id FROM departments WHERE LOWER(name) = LOWER(?) AND id <> ? AND active = 1 LIMIT 1'",
)
index = index.replace(
    "WHERE department_id = ? AND LOWER(name) = LOWER(?) AND id <> ? LIMIT 1",
    "WHERE department_id = ? AND LOWER(name) = LOWER(?) AND id <> ? AND active = 1 LIMIT 1",
)
index = index.replace(
    "WHERE department_id = ? AND UPPER(nfc_uid) = UPPER(?) AND id <> ? LIMIT 1",
    "WHERE department_id = ? AND UPPER(nfc_uid) = UPPER(?) AND id <> ? AND active = 1 LIMIT 1",
)

if 'async function deleteDepartment(request, env, departmentId)' not in index:
    marker = """async function adminCheckpoints(request, env, url) {
"""
    function_text = """async function deleteDepartment(request, env, departmentId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const existing = await getDepartmentById(env, departmentId);
  if (!existing) return json({ error: 'Sekolah tidak ditemui.' }, 404);

  const assigned = await env.DB.prepare(
    'SELECT COUNT(*) AS total FROM users WHERE department_id = ? AND active = 1',
  ).bind(departmentId).first();
  if (Number(assigned?.total || 0) > 0) {
    return json({
      error: 'Pindahkan atau nyahaktifkan semua pengguna aktif sekolah ini sebelum memadam sekolah.',
    }, 409);
  }

  await env.DB.batch([
    env.DB.prepare(
      'UPDATE departments SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
    ).bind(departmentId),
    env.DB.prepare(
      'UPDATE checkpoints SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE department_id = ?',
    ).bind(departmentId),
  ]);
  return json({ ok: true, deleted: true });
}

"""
    if marker not in index:
        raise SystemExit('index deleteDepartment insertion marker missing')
    index = index.replace(marker, function_text + marker, 1)

if 'async function deleteCheckpoint(request, env, checkpointId)' not in index:
    marker = """async function updateAdminUser(request, env, userId) {
"""
    function_text = """async function deleteCheckpoint(request, env, checkpointId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;
  const existing = await getCheckpointById(env, checkpointId);
  if (!existing) return json({ error: 'Checkpoint tidak ditemui.' }, 404);

  await env.DB.prepare(
    'UPDATE checkpoints SET active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
  ).bind(checkpointId).run();
  return json({ ok: true, deleted: true });
}

"""
    if marker not in index:
        raise SystemExit('index deleteCheckpoint insertion marker missing')
    index = index.replace(marker, function_text + marker, 1)
write(index_path, index)


# ---------------------------------------------------------------------------
# 6) Admin UI: delete school and checkpoint controls with confirmation.
# ---------------------------------------------------------------------------
maintenance_path = 'lib/features/admin/department_maintenance_screen.dart'
maintenance = read(maintenance_path)

if 'Future<void> _deleteSchool() async' not in maintenance:
    marker = """  @override
  Widget build(BuildContext context) {
    final center = LatLng(_latitude ?? 5.69582, _longitude ?? 100.53720);
"""
    method = """  Future<void> _deleteSchool() async {
    final existing = widget.department;
    if (existing == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Padam Sekolah?'),
        content: Text(
          'Padam ${existing.name} daripada tetapan RimbaKawal? Rekod sejarah akan dikekalkan. Pengguna aktif perlu dipindahkan atau dinyahaktifkan terlebih dahulu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Padam Sekolah'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.deleteDepartment(existing.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

"""
    if marker not in maintenance:
        raise SystemExit('department dialog delete method marker missing')
    maintenance = maintenance.replace(marker, method + marker, 1)

old_buttons = """            children: [
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
              ),

              const SizedBox(height: 8),
"""
new_buttons = """            children: [
              if (widget.department != null) ...[
                OutlinedButton.icon(
                  onPressed: _saving ? null : _deleteSchool,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Padam Sekolah'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
              ),

              const SizedBox(height: 8),
"""
if old_buttons in maintenance:
    maintenance = maintenance.replace(old_buttons, new_buttons, 1)

if 'Future<void> _deleteCheckpoint() async' not in maintenance:
    marker = """  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.checkpoint == null ? 'Tambah Checkpoint' : 'Edit Checkpoint',
"""
    method = """  Future<void> _deleteCheckpoint() async {
    final existing = widget.checkpoint;
    if (existing == null || _saving || _scanning) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Padam Checkpoint?'),
        content: Text(
          'Padam ${existing.name} daripada sekolah ini? Rekod rondaan lama akan dikekalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Padam Checkpoint'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.deleteCheckpoint(existing.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

"""
    if marker not in maintenance:
        raise SystemExit('checkpoint dialog delete method marker missing')
    maintenance = maintenance.replace(marker, method + marker, 1)

old_checkpoint_buttons = """            children: [
              FilledButton(
                onPressed: _saving || _scanning ? null : _save,
                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
              ),

              const SizedBox(height: 8),
"""
new_checkpoint_buttons = """            children: [
              if (widget.checkpoint != null) ...[
                OutlinedButton.icon(
                  onPressed: _saving || _scanning ? null : _deleteCheckpoint,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Padam Checkpoint'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: _saving || _scanning ? null : _save,
                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
              ),

              const SizedBox(height: 8),
"""
if old_checkpoint_buttons in maintenance:
    maintenance = maintenance.replace(old_checkpoint_buttons, new_checkpoint_buttons, 1)

write(maintenance_path, maintenance)


# ---------------------------------------------------------------------------
# Static regression assertions.
# ---------------------------------------------------------------------------
patrol = read(patrol_path)
offline = read(offline_path)
app = read(app_path)
api = read(api_path)
attendance = read(attendance_path)
index = read(index_path)
maintenance = read(maintenance_path)

assert 'if (bootstrap.routeOrderEnforced)' not in patrol
assert 'if (Boolean(department.route_order_enforced))' not in offline
assert 'if (Boolean(department.route_order_enforced))' not in app
assert 'routeOrderEnforced: false' in offline
assert 'routeOrderEnforced: false' in app
assert 'Future<void> deleteDepartment(int departmentId)' in api
assert 'Future<void> deleteCheckpoint(int checkpointId)' in api
assert 'async function deleteDepartment(request, env, departmentId)' in attendance
assert 'async function deleteCheckpoint(request, env, checkpointId)' in index
assert 'Future<void> _deleteSchool() async' in maintenance
assert 'Future<void> _deleteCheckpoint() async' in maintenance
assert "label: const Text('Padam Sekolah')" in maintenance
assert "label: const Text('Padam Checkpoint')" in maintenance

for dart_file in (ROOT / 'lib').rglob('*.dart'):
    assert 'Jabatan' not in dart_file.read_text(encoding='utf-8'), dart_file
for js_file in (ROOT / 'worker').glob('*.js'):
    assert 'Jabatan' not in js_file.read_text(encoding='utf-8'), js_file

print('Applied: flexible checkpoint order, Sekolah terminology, and delete controls.')
