from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Marker tidak ditemui: {label}')
    return text.replace(old, new, 1)


def replace_regex(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'Padanan regex tidak tepat untuk {label}: {count}')
    return updated


# -----------------------------------------------------------------------------
# Worker: admin edit user + mandatory login for each patrol session window.
# -----------------------------------------------------------------------------
worker_path = ROOT / 'worker/index.js'
worker = worker_path.read_text(encoding='utf-8')

worker = replace_once(
    worker,
    "      match = url.pathname.match(/^\\/api\\/admin\\/users\\/(\\d+)\\/department$/);\n      if (match && request.method === 'PUT') {\n        return updateUserDepartment(request, env, Number(match[1]));\n      }\n",
    "      match = url.pathname.match(/^\\/api\\/admin\\/users\\/(\\d+)$/);\n      if (match && request.method === 'PUT') {\n        return updateAdminUser(request, env, Number(match[1]));\n      }\n\n      match = url.pathname.match(/^\\/api\\/admin\\/users\\/(\\d+)\\/department$/);\n      if (match && request.method === 'PUT') {\n        return updateUserDepartment(request, env, Number(match[1]));\n      }\n",
    'route update admin user',
)

worker = replace_once(
    worker,
    '  const token = randomToken();\n',
    "  const token = `${Date.now().toString(36)}.${randomToken()}`;\n",
    'timestamped login token',
)

update_admin_user = r'''async function updateAdminUser(request, env, userId) {
  const auth = await requireManagement(request, env);
  if (auth.response) return auth.response;

  const body = await readJson(request);
  const nama = String(body.nama ?? '').trim().toUpperCase();
  const jawatan = String(body.jawatan ?? '').trim();
  const departmentId = Number(body.departmentId);

  if (nama.length < 3) return json({ error: 'Nama pengguna tidak sah.' }, 400);
  if (!['Patrol', 'Supervisor', 'Management'].includes(jawatan)) {
    return json({ error: 'Jawatan pengguna tidak sah.' }, 400);
  }
  if (!Number.isInteger(departmentId) || departmentId <= 0) {
    return json({ error: 'Pilih Jabatan pengguna.' }, 400);
  }

  const department = await env.DB.prepare(
    'SELECT id, name, active FROM departments WHERE id = ? LIMIT 1',
  ).bind(departmentId).first();
  if (!department || Number(department.active) !== 1) {
    return json({ error: 'Jabatan aktif tidak ditemui.' }, 404);
  }

  const user = await getUserById(env, userId);
  if (!user) return json({ error: 'Pengguna tidak ditemui.' }, 404);

  let profilePicture = user.profile_picture || null;
  if (body.clearProfilePicture === true) {
    profilePicture = null;
  } else if (Object.prototype.hasOwnProperty.call(body, 'profilePicture')) {
    const picture = String(body.profilePicture ?? '');
    if (!/^data:image\/(jpeg|png|webp);base64,/i.test(picture)) {
      return json({ error: 'Format gambar mesti JPEG, PNG atau WebP.' }, 400);
    }
    if (picture.length > 700000) {
      return json({ error: 'Gambar terlalu besar. Had selepas pemampatan ialah kira-kira 500 KB.' }, 413);
    }
    profilePicture = picture;
  }

  await env.DB.prepare(
    `UPDATE users
     SET nama = ?, jawatan = ?, department_id = ?, jabatan = ?, profile_picture = ?
     WHERE id = ?`,
  ).bind(nama, jawatan, departmentId, department.name, profilePicture, userId).run();

  const updated = await getUserById(env, userId);
  return json({ user: publicUser(updated) });
}

'''

worker = replace_once(
    worker,
    'async function updateUserDepartment(request, env, userId) {',
    update_admin_user + 'async function updateUserDepartment(request, env, userId) {',
    'function update admin user',
)

new_require_user = r'''async function requireUser(request, env) {
  const token = getSessionToken(request);
  if (!token) {
    return { response: json({ error: 'Sesi tidak sah. Sila log masuk.' }, 401) };
  }

  const tokenHash = await sha256(token);
  const session = await env.DB.prepare(
    `SELECT user_id, expires_at_ms, created_at
     FROM sessions
     WHERE token_hash = ? AND expires_at_ms > ?
     LIMIT 1`,
  ).bind(tokenHash, Date.now()).first();

  if (!session) {
    return { response: json({ error: 'Sesi telah tamat. Sila log masuk semula.' }, 401) };
  }

  const user = await getUserById(env, session.user_id);
  if (!user || Number(user.active) !== 1) {
    await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(tokenHash).run();
    return { response: json({ error: 'Pengguna tidak aktif. Sila log masuk semula.' }, 401) };
  }

  const interval = Math.max(15, Math.min(1440, Number(user.session_interval_minutes || 120)));
  const window = sessionWindow(new Date(), interval, user.session_start_minutes);
  const rawCreatedAt = String(session.created_at || '').trim().replace(' ', 'T');
  const createdAtMs = Date.parse(rawCreatedAt.endsWith('Z') ? rawCreatedAt : `${rawCreatedAt}Z`);

  if (!Number.isFinite(createdAtMs) || createdAtMs < window.startMs) {
    await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(tokenHash).run();
    return {
      response: json(
        { error: 'Sesi Rondaan baharu telah bermula. Sila log masuk semula.' },
        401,
      ),
    };
  }

  return { user };
}

function userSelect'''

worker = replace_regex(
    worker,
    r'async function requireUser\(request, env\) \{.*?\n\}\n\nfunction userSelect',
    new_require_user,
    'requireUser session-window validation',
)

worker_path.write_text(worker, encoding='utf-8')


# -----------------------------------------------------------------------------
# API client: preserve offline access only within the same login session window,
# and add admin update endpoint.
# -----------------------------------------------------------------------------
api_path = ROOT / 'lib/core/api/api_service.dart'
api = api_path.read_text(encoding='utf-8')

new_get_session = r'''  Future<AppUser?> getSession() async {
    if (_sessionToken == null || _sessionToken!.isEmpty) {
      await _offline.clearCachedUser();
      return null;
    }

    final cached = await _offline.cachedUser();
    if (cached != null && !_tokenBelongsToCurrentSession(cached)) {
      _sessionToken = null;
      await _vault.clearToken();
      await _offline.clearCachedUser();
      return null;
    }

    try {
      final response = await http.get(
        _uri('/api/auth/session'),
        headers: _headers(),
      );
      if (response.statusCode == 401) {
        _sessionToken = null;
        await _vault.clearToken();
        await _offline.clearCachedUser();
        return null;
      }
      final user = AppUser.fromJson(
        Map<String, dynamic>.from(_decode(response)['user'] as Map),
      );
      if (!_tokenBelongsToCurrentSession(user)) {
        _sessionToken = null;
        await _vault.clearToken();
        await _offline.clearCachedUser();
        return null;
      }
      await _offline.cacheUser(user);
      return user;
    } catch (_) {
      if (cached != null && _tokenBelongsToCurrentSession(cached)) {
        return cached;
      }
      return null;
    }
  }

'''

api = replace_regex(
    api,
    r'  Future<AppUser\?> getSession\(\) async \{.*?\n  \}\n\n  Future<void> logout\(\) async \{',
    new_get_session + '  Future<void> logout() async {',
    'client getSession enforcement',
)

admin_method = r'''  Future<AppUser> updateAdminUser({
    required int userId,
    required String nama,
    required String jawatan,
    required int departmentId,
    String? profilePicture,
    bool clearProfilePicture = false,
  }) async {
    final body = <String, dynamic>{
      'nama': nama,
      'jawatan': jawatan,
      'departmentId': departmentId,
      if (profilePicture != null) 'profilePicture': profilePicture,
      if (clearProfilePicture) 'clearProfilePicture': true,
    };
    final data = _decode(
      await http.put(
        _uri('/api/admin/users/$userId'),
        headers: _headers(jsonBody: true),
        body: jsonEncode(body),
      ),
    );
    return AppUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

'''

api = replace_once(
    api,
    '  Future<AppUser> updateUserDepartment(int userId, int departmentId) async {',
    admin_method + '  Future<AppUser> updateUserDepartment(int userId, int departmentId) async {',
    'api update admin user',
)

session_helpers = r'''  bool _tokenBelongsToCurrentSession(AppUser user) {
    final token = _sessionToken;
    if (token == null || token.isEmpty) return false;
    final separator = token.indexOf('.');
    if (separator <= 0) return false;
    final encodedTime = token.substring(0, separator);
    final issuedAtMs = int.tryParse(encodedTime, radix: 36);
    if (issuedAtMs == null || issuedAtMs <= 0) return false;
    final sessionStart = _currentSessionStartUtc(user);
    return !DateTime.fromMillisecondsSinceEpoch(
      issuedAtMs,
      isUtc: true,
    ).isBefore(sessionStart);
  }

  DateTime _currentSessionStartUtc(AppUser user) {
    final malaysiaNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    final interval = user.sessionIntervalMinutes.clamp(15, 1440);
    final startMinutes = user.sessionStartMinutes.clamp(0, 1439);
    final minuteOfDay = malaysiaNow.hour * 60 + malaysiaNow.minute;
    var scheduleDay = DateTime.utc(
      malaysiaNow.year,
      malaysiaNow.month,
      malaysiaNow.day,
    );
    if (minuteOfDay < startMinutes) {
      scheduleDay = scheduleDay.subtract(const Duration(days: 1));
    }
    final anchor = scheduleDay.add(Duration(minutes: startMinutes));
    final elapsedMinutes = malaysiaNow.difference(anchor).inMinutes;
    final sessionIndex = elapsedMinutes ~/ interval;
    final malaysiaSessionStart = anchor.add(
      Duration(minutes: sessionIndex * interval),
    );
    return malaysiaSessionStart.subtract(const Duration(hours: 8));
  }

'''

api = replace_once(
    api,
    '  Map<String, dynamic> _decode(http.Response response) {',
    session_helpers + '  Map<String, dynamic> _decode(http.Response response) {',
    'client session helper',
)

api_path.write_text(api, encoding='utf-8')


# -----------------------------------------------------------------------------
# Login screen: allow a mandatory relogin notice.
# -----------------------------------------------------------------------------
login_path = ROOT / 'lib/features/auth/login_screen.dart'
login = login_path.read_text(encoding='utf-8')

login = replace_once(
    login,
    "    required this.mockMode,\n    super.key,\n  });\n\n  final NfcService nfcService;\n  final bool mockMode;\n",
    "    required this.mockMode,\n    this.notice,\n    super.key,\n  });\n\n  final NfcService nfcService;\n  final bool mockMode;\n  final String? notice;\n",
    'login notice field',
)

login = replace_once(
    login,
    "                              const SizedBox(height: 24),\n                              TextFormField(\n",
    "                              if (widget.notice != null && widget.notice!.isNotEmpty) ...[\n                                Container(\n                                  width: double.infinity,\n                                  padding: const EdgeInsets.all(14),\n                                  decoration: BoxDecoration(\n                                    color: const Color(0xFF4834D4).withValues(alpha: 0.16),\n                                    borderRadius: BorderRadius.circular(14),\n                                    border: Border.all(\n                                      color: const Color(0xFF6C5CE7).withValues(alpha: 0.35),\n                                    ),\n                                  ),\n                                  child: Text(\n                                    widget.notice!,\n                                    style: const TextStyle(\n                                      color: Color(0xFFD6D0FF),\n                                      fontWeight: FontWeight.w700,\n                                    ),\n                                  ),\n                                ),\n                                const SizedBox(height: 16),\n                              ],\n                              const SizedBox(height: 24),\n                              TextFormField(\n",
    'login notice UI',
)

login_path.write_text(login, encoding='utf-8')


# -----------------------------------------------------------------------------
# Dashboard: force logout immediately at every new session boundary.
# -----------------------------------------------------------------------------
dash_path = ROOT / 'lib/features/dashboard/dashboard_screen.dart'
dash = dash_path.read_text(encoding='utf-8')

dash = replace_once(
    dash,
    '  bool _alarmShowing = false;\n',
    '  bool _alarmShowing = false;\n  bool _forcingRelogin = false;\n',
    'dashboard forcing flag',
)

dash = replace_once(
    dash,
    '    final local = value.toLocal();\n',
    "    final local = value.toUtc().add(const Duration(hours: 8));\n",
    'Malaysia session clock',
)

new_boundary = r'''  void _checkSessionBoundary() {
    final current = _sessionKey(DateTime.now());
    if (_lastSessionKey == null) {
      _lastSessionKey = current;
      return;
    }
    if (current == _lastSessionKey) return;
    _lastSessionKey = current;
    unawaited(_forceReloginForNewSession());
  }

  Future<void> _forceReloginForNewSession() async {
    if (_forcingRelogin || !mounted) return;
    _forcingRelogin = true;
    try {
      await _alarmPlayer.stop();
      try {
        await NotificationService.instance.unregisterCurrentDevice();
      } catch (_) {}
      await widget.api.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(
            nfcService: widget.nfcService,
            mockMode: widget.mockMode,
            notice: 'Sesi Rondaan baharu telah bermula. Sila log masuk semula untuk meneruskan.',
          ),
        ),
        (_) => false,
      );
    } finally {
      _forcingRelogin = false;
    }
  }

'''

dash = replace_regex(
    dash,
    r'  void _checkSessionBoundary\(\) \{.*?\n  \}\n\n  Future<void> _playAlarm\(\) async \{',
    new_boundary + '  Future<void> _playAlarm() async {',
    'dashboard session boundary relogin',
)

dash_path.write_text(dash, encoding='utf-8')


# -----------------------------------------------------------------------------
# Admin user maintenance: edit name, role, department and profile picture.
# -----------------------------------------------------------------------------
admin_path = ROOT / 'lib/features/admin/user_maintenance_screen.dart'
admin = admin_path.read_text(encoding='utf-8')

admin = replace_once(
    admin,
    "import 'package:flutter/material.dart';\n",
    "import 'dart:convert';\n\nimport 'package:flutter/material.dart';\nimport 'package:image_picker/image_picker.dart';\n",
    'admin image imports',
)

edit_handler = r'''  Future<void> _editUser(
    AppUser user,
    List<DepartmentRecord> departments,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _EditUserDialog(
        api: widget.api,
        user: user,
        departments: departments,
      ),
    );
    if (changed == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil pengguna berjaya dikemas kini.')),
      );
    }
  }

  ImageProvider<Object>? _imageProvider(String? picture) {
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/') && picture.contains(',')) {
      try {
        return MemoryImage(base64Decode(picture.split(',').last));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(picture);
  }

'''

admin = replace_regex(
    admin,
    r'  Future<void> _changeDepartment\(.*?\n  \}\n\n  @override\n  Widget build',
    edit_handler + '  @override\n  Widget build',
    'replace department-only editor',
)

admin = replace_once(
    admin,
    '                  onTap: () => _changeDepartment(user, data.departments),\n                  leading: CircleAvatar(\n                    child: Text(user.nama.isEmpty ? \'?\' : user.nama[0]),\n                  ),\n',
    "                  onTap: () => _editUser(user, data.departments),\n                  leading: CircleAvatar(\n                    backgroundImage: _imageProvider(user.profilePicture),\n                    child: _imageProvider(user.profilePicture) == null\n                        ? Text(user.nama.isEmpty ? '?' : user.nama[0])\n                        : null,\n                  ),\n",
    'user list avatar and edit tap',
)

admin = replace_once(
    admin,
    '                  trailing: const Icon(Icons.edit_location_alt_rounded),\n',
    '                  trailing: const Icon(Icons.edit_rounded),\n',
    'edit icon',
)

edit_dialog = r'''class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({
    required this.api,
    required this.user,
    required this.departments,
  });

  final ApiService api;
  final AppUser user;
  final List<DepartmentRecord> departments;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _nameController;
  late String _jawatan;
  int? _departmentId;
  String? _newProfilePicture;
  bool _clearProfilePicture = false;
  bool _saving = false;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.nama);
    _jawatan = widget.user.jawatan;
    _departmentId = widget.user.departmentId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _imageMimeType(XFile file) {
    final mime = file.mimeType?.toLowerCase();
    if (mime == 'image/jpeg' || mime == 'image/png' || mime == 'image/webp') {
      return mime;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return null;
  }

  ImageProvider<Object>? _previewImage() {
    final picture = _clearProfilePicture
        ? null
        : (_newProfilePicture ?? widget.user.profilePicture);
    if (picture == null || picture.isEmpty) return null;
    if (picture.startsWith('data:image/') && picture.contains(',')) {
      try {
        return MemoryImage(base64Decode(picture.split(',').last));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(picture);
  }

  Future<void> _pickProfilePicture() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 75,
        requestFullMetadata: false,
      );
      if (picked == null || !mounted) return;
      final mime = _imageMimeType(picked);
      if (mime == null) {
        setState(() => _error = 'Gunakan gambar JPEG, PNG atau WebP.');
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.length > 500000) {
        setState(() => _error = 'Gambar terlalu besar. Pilih gambar lain yang lebih kecil.');
        return;
      }
      setState(() {
        _newProfilePicture = 'data:$mime;base64,${base64Encode(bytes)}';
        _clearProfilePicture = false;
        _error = null;
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final nama = _nameController.text.trim();
    if (nama.length < 3 || _departmentId == null) {
      setState(() => _error = 'Lengkapkan nama dan Jabatan pengguna.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateAdminUser(
        userId: widget.user.id,
        nama: nama,
        jawatan: _jawatan,
        departmentId: _departmentId!,
        profilePicture: _newProfilePicture,
        clearProfilePicture: _clearProfilePicture,
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

  @override
  Widget build(BuildContext context) {
    final active = widget.departments.where((item) => item.active).toList();
    final preview = _previewImage();
    return AlertDialog(
      title: const Text('Edit Pengguna'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundImage: preview,
                    child: preview == null
                        ? Text(
                            _nameController.text.trim().isEmpty
                                ? '?'
                                : _nameController.text.trim()[0],
                            style: const TextStyle(fontSize: 30),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -8,
                    bottom: -8,
                    child: IconButton.filled(
                      tooltip: 'Tukar gambar profil',
                      onPressed: _picking ? null : _pickProfilePicture,
                      icon: _picking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_a_photo_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _newProfilePicture = null;
                          _clearProfilePicture = true;
                        }),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Buang gambar profil'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Nama Pengguna',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: widget.user.noKadPengenalan,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'No. Kad Pengenalan',
                  prefixIcon: Icon(Icons.badge_outlined),
                  helperText: 'ID login tidak diubah dari skrin ini.',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _jawatan,
                decoration: const InputDecoration(
                  labelText: 'Jawatan',
                  prefixIcon: Icon(Icons.work_outline_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'Patrol', child: Text('Pengawal Rondaan')),
                  DropdownMenuItem(value: 'Supervisor', child: Text('Penyelia')),
                  DropdownMenuItem(value: 'Management', child: Text('Pengurusan')),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _jawatan = value);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _departmentId,
                decoration: const InputDecoration(
                  labelText: 'Jabatan',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                items: active
                    .map(
                      (department) => DropdownMenuItem<int>(
                        value: department.id,
                        child: Text(department.name),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _departmentId = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
        ),
      ],
    );
  }
}

'''

admin = replace_once(
    admin,
    'class _UserAdminData {',
    edit_dialog + 'class _UserAdminData {',
    'admin edit dialog class',
)

admin_path.write_text(admin, encoding='utf-8')


# -----------------------------------------------------------------------------
# Validate expected markers after patch.
# -----------------------------------------------------------------------------
checks = {
    worker_path: [
        'async function updateAdminUser(request, env, userId)',
        'Sesi Rondaan baharu telah bermula. Sila log masuk semula.',
        'Date.now().toString(36)',
    ],
    api_path: [
        'Future<AppUser> updateAdminUser({',
        '_tokenBelongsToCurrentSession',
        'int.tryParse(encodedTime, radix: 36)',
    ],
    login_path: [
        'final String? notice;',
        'widget.notice!',
    ],
    dash_path: [
        '_forceReloginForNewSession',
        'Sila log masuk semula untuk meneruskan.',
    ],
    admin_path: [
        "title: const Text('Edit Pengguna')",
        'Tukar gambar profil',
        'updateAdminUser(',
    ],
}

for path, markers in checks.items():
    text = path.read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'Validasi gagal: {marker} tiada dalam {path}')

print('Admin profile editing + mandatory per-session relogin patch applied.')
