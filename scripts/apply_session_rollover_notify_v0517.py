from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def write(path, text):
    (ROOT / path).write_text(text, encoding='utf-8')


def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f'Marker tidak ditemui: {label}')
    return text.replace(old, new, 1)


def replace_regex(text, pattern, replacement, label):
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'Padanan regex tidak tepat untuk {label}: {count}')
    return updated


# Version ---------------------------------------------------------------------
pubspec = read('pubspec.yaml')
pubspec = replace_once(pubspec, 'version: 0.5.16+32', 'version: 0.5.17+33', 'version bump')
write('pubspec.yaml', pubspec)


# Push worker: device-targeted sending + notification collapse keys + ordered
# warning/start notifications at every session boundary.
push = read('worker/push.js')

push = replace_once(
    push,
    "export async function sendPushToUser(env, userId, payload) {\n  if (!pushConfigured(env) || !userId) return { sent: 0, configured: false };\n  const result = await env.DB.prepare(\n    `SELECT id, token, user_id FROM push_devices\n     WHERE user_id = ? AND active = 1`,\n  ).bind(userId).all();\n  return sendToRows(env, result.results ?? [], payload);\n}\n",
    "export async function sendPushToUser(env, userId, payload) {\n  if (!pushConfigured(env) || !userId) return { sent: 0, configured: false };\n  const result = await env.DB.prepare(\n    `SELECT id, token, user_id FROM push_devices\n     WHERE user_id = ? AND active = 1`,\n  ).bind(userId).all();\n  return sendToRows(env, result.results ?? [], payload);\n}\n\nexport async function sendPushToDevice(env, userId, token, payload) {\n  const deviceToken = String(token ?? '').trim();\n  if (!pushConfigured(env) || !userId || !deviceToken) {\n    return { sent: 0, configured: pushConfigured(env) };\n  }\n  const row = await env.DB.prepare(\n    `SELECT id, token, user_id FROM push_devices\n     WHERE user_id = ? AND token = ? AND active = 1\n     LIMIT 1`,\n  ).bind(userId, deviceToken).first();\n  if (!row) return { sent: 0, configured: true, registered: false };\n  return { ...(await sendToRows(env, [row], payload)), registered: true };\n}\n",
    'device-targeted push helper',
)

push = replace_once(
    push,
    "async function sendToRows(env, rows, payload) {\n  if (rows.length === 0) return { sent: 0, configured: true };",
    "async function sendToRows(env, rows, payload) {\n  if (rows.length === 0) return { sent: 0, configured: true };\n  const collapseKey = String(payload.collapseKey ?? '').trim().slice(0, 64);",
    'collapse key variable',
)

push = replace_once(
    push,
    "              android: {\n                priority: 'HIGH',\n                notification: { sound: 'default' },\n              },\n              apns: {\n                headers: { 'apns-priority': '10' },\n                payload: { aps: { sound: 'default' } },\n              },\n              webpush: {\n                headers: { Urgency: 'high' },\n                notification: {\n                  icon: '/icons/Icon-192.png',\n                  badge: '/icons/Icon-192.png',\n                },\n              },",
    "              android: {\n                priority: 'HIGH',\n                notification: {\n                  sound: 'default',\n                  ...(collapseKey ? { tag: collapseKey } : {}),\n                },\n              },\n              apns: {\n                headers: {\n                  'apns-priority': '10',\n                  ...(collapseKey ? { 'apns-collapse-id': collapseKey } : {}),\n                },\n                payload: { aps: { sound: 'default' } },\n              },\n              webpush: {\n                headers: { Urgency: 'high' },\n                notification: {\n                  icon: '/icons/Icon-192.png',\n                  badge: '/icons/Icon-192.png',\n                  ...(collapseKey ? { tag: collapseKey } : {}),\n                },\n              },",
    'platform notification collapse keys',
)

old_boundary = """    if (minuteIntoSession === 0) {
      await autoCloseExpiredLivePatrols(env, department.id, window.start);
      if (await claimDispatch(env, `session:${department.id}:${window.dayKey}:${window.index}`, 'session_start')) {
        await sendPushToDepartment(env, department.id, {
          title: `Sesi Rondaan ${window.index + 1} Bermula`,
          body: `${department.name} • ${hmFromDate(window.start)}–${hmFromDate(window.end)}. Sila mulakan rondaan dan lengkapkan checkpoint.`,
          kind: 'session_start',
          data: commonData,
          roles: ['patrol', 'supervisor'],
        });
      }
      const previous = sessionWindowAt(new Date(window.start.getTime() - 60000), interval, startMinutes);
      await dispatchPreviousOutcome(env, department, previous);
    }
"""
new_boundary = """    if (minuteIntoSession === 0) {
      await autoCloseExpiredLivePatrols(env, department.id, window.start);
      const collapseSuffix = `${department.id}-${window.dayKey}-${window.index}`;
      if (await claimDispatch(env, `session-logout:${collapseSuffix}`, 'session_logout_warning')) {
        await sendPushToDepartment(env, department.id, {
          title: 'Sesi Baharu • Log Masuk Semula',
          body: `Sesi Rondaan ${window.index + 1} telah bermula. Peranti ini akan log keluar dan anda perlu log masuk semula.`,
          kind: 'session_logout_warning',
          data: commonData,
          roles: ['patrol', 'supervisor', 'management'],
          collapseKey: `rk-session-logout-${collapseSuffix}`,
        });
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
      if (await claimDispatch(env, `session:${department.id}:${window.dayKey}:${window.index}`, 'session_start')) {
        await sendPushToDepartment(env, department.id, {
          title: `Sesi Rondaan ${window.index + 1} Bermula`,
          body: `${department.name} • ${hmFromDate(window.start)}–${hmFromDate(window.end)}. Sila log masuk semula dan mulakan rondaan.`,
          kind: 'session_start',
          data: commonData,
          roles: ['patrol', 'supervisor', 'management'],
          collapseKey: `rk-session-start-${collapseSuffix}`,
        });
      }
      const previous = sessionWindowAt(new Date(window.start.getTime() - 60000), interval, startMinutes);
      await dispatchPreviousOutcome(env, department, previous);
    }
"""
push = replace_once(push, old_boundary, new_boundary, 'ordered scheduled rollover notifications')
write('worker/push.js', push)


# SOS/router worker: special rollover endpoint deliberately authenticates the
# still-existing cloud session without enforcing the new patrol window. It
# targets the exact current device token and returns success only when BOTH
# notifications are accepted by FCM for that device.
sos = read('worker/sos.js')
sos = replace_once(
    sos,
    "import { dispatchSessionStartNotifications, pushConfigured, registerPushDevice, sendPushToUser, unregisterPushDevice } from './push.js';",
    "import { dispatchSessionStartNotifications, pushConfigured, registerPushDevice, sendPushToDevice, sendPushToUser, unregisterPushDevice } from './push.js';",
    'sendPushToDevice import',
)

sos = replace_once(
    sos,
    "      if (url.pathname === '/api/push/status' && request.method === 'GET') {\n        const auth = await requireUser(request, env);\n        if (auth.response) return auth.response;\n        return json({ configured: pushConfigured(env) });\n      }\n",
    "      if (url.pathname === '/api/push/status' && request.method === 'GET') {\n        const auth = await requireUser(request, env);\n        if (auth.response) return auth.response;\n        return json({ configured: pushConfigured(env) });\n      }\n      if (url.pathname === '/api/push/session-rollover' && request.method === 'POST') {\n        const auth = await requireUser(request, env);\n        if (auth.response) return auth.response;\n        return prepareSessionRollover(env, auth.user, await readJson(request));\n      }\n",
    'session rollover route',
)

rollover_fn = r'''async function prepareSessionRollover(env, user, body) {
  const deviceToken = String(body?.token ?? '').trim();
  if (!deviceToken) {
    return json({ ok: false, ready: false, error: 'Token push peranti tidak tersedia.' }, 409);
  }
  if (!user.department_id) {
    return json({ ok: false, ready: false, error: 'Pengguna belum dipautkan kepada Jabatan.' }, 409);
  }

  const interval = Math.max(15, Math.min(1440, Number(user.session_interval_minutes || 120)));
  const startMinutes = Math.max(0, Math.min(1439, Number(user.session_start_minutes ?? 420)));
  const window = rolloverSessionWindow(new Date(), interval, startMinutes);
  const collapseSuffix = `${user.department_id}-${window.dayKey}-${window.index}`;
  const data = {
    sessionIndex: window.index + 1,
    sessionDate: window.dayKey,
    departmentId: user.department_id,
    rollover: '1',
  };

  const warning = await sendPushToDevice(env, user.id, deviceToken, {
    title: 'Sesi Baharu • Peranti Akan Log Keluar',
    body: `Sesi Rondaan ${window.index + 1} telah bermula. RimbaKawal akan log keluar selepas pemberitahuan sesi baharu berjaya dihantar.`,
    kind: 'session_logout_warning',
    data: { ...data, sequence: '1' },
    collapseKey: `rk-session-logout-${collapseSuffix}`,
  });
  if (Number(warning.sent || 0) < 1) {
    return json({
      ok: false,
      ready: false,
      warningSent: Number(warning.sent || 0),
      sessionSent: 0,
      registered: warning.registered !== false,
      error: 'Pemberitahuan log keluar belum berjaya dihantar ke peranti ini.',
    }, 503);
  }

  await new Promise((resolve) => setTimeout(resolve, 300));

  const started = await sendPushToDevice(env, user.id, deviceToken, {
    title: `Sesi Rondaan ${window.index + 1} Bermula`,
    body: `${user.department_name || user.jabatan || 'Jabatan'} • ${rolloverHm(window.start)}–${rolloverHm(window.end)}. Sila log masuk semula dan mulakan rondaan.`,
    kind: 'session_start',
    data: { ...data, sequence: '2' },
    collapseKey: `rk-session-start-${collapseSuffix}`,
  });

  const ready = Number(started.sent || 0) >= 1;
  return json({
    ok: ready,
    ready,
    warningSent: Number(warning.sent || 0),
    sessionSent: Number(started.sent || 0),
    registered: started.registered !== false,
    sessionIndex: window.index + 1,
    sessionDate: window.dayKey,
    error: ready ? null : 'Pemberitahuan sesi baharu belum berjaya dihantar ke peranti ini.',
  }, ready ? 200 : 503);
}

function rolloverSessionWindow(date, intervalMinutes, startMinutes) {
  const offsetMs = 8 * 60 * 60 * 1000;
  const malaysiaMs = date.getTime() + offsetMs;
  const local = new Date(malaysiaMs);
  const minuteOfDay = local.getUTCHours() * 60 + local.getUTCMinutes();
  let anchorMalaysiaMs = Date.UTC(
    local.getUTCFullYear(),
    local.getUTCMonth(),
    local.getUTCDate(),
  ) + startMinutes * 60000;
  if (minuteOfDay < startMinutes) anchorMalaysiaMs -= 86400000;
  const elapsedMinutes = Math.floor((malaysiaMs - anchorMalaysiaMs) / 60000);
  const index = Math.max(0, Math.floor(elapsedMinutes / intervalMinutes));
  const startMalaysiaMs = anchorMalaysiaMs + index * intervalMinutes * 60000;
  const endMalaysiaMs = startMalaysiaMs + intervalMinutes * 60000;
  const startLocal = new Date(startMalaysiaMs);
  const yyyy = startLocal.getUTCFullYear();
  const mm = String(startLocal.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(startLocal.getUTCDate()).padStart(2, '0');
  return {
    index,
    dayKey: `${yyyy}-${mm}-${dd}`,
    start: new Date(startMalaysiaMs - offsetMs),
    end: new Date(endMalaysiaMs - offsetMs),
  };
}

function rolloverHm(date) {
  const local = new Date(date.getTime() + 8 * 60 * 60 * 1000);
  return `${String(local.getUTCHours()).padStart(2, '0')}:${String(local.getUTCMinutes()).padStart(2, '0')}`;
}

'''
sos = replace_once(sos, 'async function getSosAlerts(request, env) {', rollover_fn + 'async function getSosAlerts(request, env) {', 'rollover function')

sos = replace_once(
    sos,
    "            u.jabatan, u.active, u.department_id,\n            COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes",
    "            u.jabatan, u.active, u.department_id,\n            COALESCE(d.name, u.jabatan) AS department_name,\n            COALESCE(d.session_interval_minutes, 120) AS session_interval_minutes,\n            COALESCE(d.session_start_minutes, 420) AS session_start_minutes",
    'rollover user schedule fields',
)
write('worker/sos.js', sos)


# Keep stale session DB row until explicit logout so the rollover endpoint can
# authenticate after the patrol boundary. Normal protected APIs still return
# 401, so this does not extend usable patrol access.
index = read('worker/index.js')
index = replace_once(
    index,
    "  if (!Number.isFinite(createdAtMs) || createdAtMs < window.startMs) {\n    await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(tokenHash).run();\n    return {",
    "  if (!Number.isFinite(createdAtMs) || createdAtMs < window.startMs) {\n    return {",
    'preserve stale session for rollover handshake',
)
write('worker/index.js', index)


# API client ------------------------------------------------------------------
api = read('lib/core/api/api_service.dart')
api = replace_once(
    api,
    "  Future<void> unregisterPushDevice(String token) async {\n    _decode(\n      await http.post(\n        _uri('/api/push/unregister'),\n        headers: _headers(jsonBody: true),\n        body: jsonEncode({'token': token}),\n      ),\n    );\n  }\n",
    "  Future<void> unregisterPushDevice(String token) async {\n    _decode(\n      await http.post(\n        _uri('/api/push/unregister'),\n        headers: _headers(jsonBody: true),\n        body: jsonEncode({'token': token}),\n      ),\n    );\n  }\n\n  Future<Map<String, dynamic>> prepareSessionRollover(String pushToken) async {\n    return _decode(\n      await http.post(\n        _uri('/api/push/session-rollover'),\n        headers: _headers(jsonBody: true),\n        body: jsonEncode({'token': pushToken}),\n      ),\n    );\n  }\n",
    'session rollover API method',
)
write('lib/core/api/api_service.dart', api)


# Notification service: retain device token on automatic session logout.
notify = read('lib/core/notifications/notification_service.dart')
notify = replace_once(
    notify,
    "  bool _ready = false;\n  bool _initializing = false;\n\n  bool get configured => PushConfig.isConfigured;\n  bool get ready => _ready;",
    "  bool _ready = false;\n  bool _initializing = false;\n  bool _sessionRolloverInProgress = false;\n\n  bool get configured => PushConfig.isConfigured;\n  bool get ready => _ready;\n  bool get sessionRolloverInProgress => _sessionRolloverInProgress;\n  String? get currentToken => _token;",
    'rollover notification state fields',
)

notify = replace_once(
    notify,
    "  Future<void> unregisterCurrentDevice() async {",
    "  void beginSessionRollover() {\n    _sessionRolloverInProgress = true;\n  }\n\n  void finishSessionRollover() {\n    _sessionRolloverInProgress = false;\n  }\n\n  void detachUserKeepPushToken() {\n    _user = null;\n    _pendingOpenedAlert = null;\n  }\n\n  Future<void> unregisterCurrentDevice() async {",
    'keep-token logout helpers',
)
write('lib/core/notifications/notification_service.dart', notify)


# Foreground rollover pushes should be visible but non-blocking; avoid opening
# two AlertDialogs immediately before the login screen replaces the dashboard.
gate = read('lib/core/notifications/notification_alert_gate.dart')
gate = replace_once(
    gate,
    "    // SOS has a dedicated full-screen alarm/polling experience.\n    if (alert.kind == 'sos') return;\n",
    "    // SOS has a dedicated full-screen alarm/polling experience.\n    if (alert.kind == 'sos') return;\n\n    if (NotificationService.instance.sessionRolloverInProgress &&\n        (alert.kind == 'session_logout_warning' ||\n            alert.kind == 'session_start')) {\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          content: Text('${alert.title}\\n${alert.body}'),\n          duration: const Duration(milliseconds: 1100),\n        ),\n      );\n      return;\n    }\n",
    'non-blocking foreground rollover messages',
)
write('lib/core/notifications/notification_alert_gate.dart', gate)


# Dashboard: do not advance the remembered session key until BOTH pushes to the
# exact current device are accepted by FCM. Retry on the next 15-second tick if
# not ready. Automatic rollover logout keeps the FCM device registration.
dash = read('lib/features/dashboard/dashboard_screen.dart')

new_boundary = r'''  void _checkSessionBoundary() {
    final current = _sessionKey(DateTime.now());
    if (_lastSessionKey == null) {
      _lastSessionKey = current;
      return;
    }
    if (current == _lastSessionKey || _forcingRelogin) return;
    unawaited(_forceReloginForNewSession(current));
  }

  Future<void> _forceReloginForNewSession(String newSessionKey) async {
    if (_forcingRelogin || !mounted) return;
    _forcingRelogin = true;
    final notifications = NotificationService.instance;
    notifications.beginSessionRollover();
    try {
      var token = notifications.currentToken;
      if (token == null || token.isEmpty) {
        await notifications.bindUser(_user);
        token = notifications.currentToken;
      }

      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Auto logout ditangguhkan: push notification belum aktif pada peranti ini.',
              ),
            ),
          );
        }
        return;
      }

      Map<String, dynamic>? handshake;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final result = await widget.api.prepareSessionRollover(token);
          if (result['ready'] == true) {
            handshake = result;
            break;
          }
        } catch (_) {}
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
      }

      if (handshake == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pemberitahuan sesi baharu belum berjaya dihantar. RimbaKawal akan cuba semula sebelum auto logout.',
              ),
            ),
          );
        }
        return;
      }

      // Only mark the boundary as handled after both notifications were
      // accepted for this exact device.
      _lastSessionKey = newSessionKey;
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await widget.api.logout();
      notifications.detachUserKeepPushToken();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(
            nfcService: widget.nfcService,
            mockMode: widget.mockMode,
            notice:
                'Sesi Rondaan baharu telah bermula. Pemberitahuan telah dihantar dan peranti dilog keluar. Sila log masuk semula untuk meneruskan.',
          ),
        ),
        (_) => false,
      );
    } finally {
      notifications.finishSessionRollover();
      _forcingRelogin = false;
    }
  }

'''
dash = replace_regex(
    dash,
    r'  void _checkSessionBoundary\(\) \{.*?\n  \}\n\n  Future<void> _forceReloginForNewSession\(\) async \{.*?\n  \}\n\n  Future<void> _bindNotifications',
    new_boundary + '  Future<void> _bindNotifications',
    'notify-before-logout dashboard flow',
)
write('lib/features/dashboard/dashboard_screen.dart', dash)

print('Applied session rollover notification sequencing v0.5.17')
