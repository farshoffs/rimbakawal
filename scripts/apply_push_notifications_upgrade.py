from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text()


def write(path, text):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)

# 1) Flutter dependencies/version.
pubspec = read('pubspec.yaml')
pubspec = re.sub(r'^version: .+$', 'version: 0.4.0+4', pubspec, count=1, flags=re.M)
pubspec = replace_once(
    pubspec,
    '  cupertino_icons: ^1.0.8\n',
    '  cupertino_icons: ^1.0.8\n  firebase_core: ^4.14.0\n  firebase_messaging: ^16.6.0\n',
    'firebase dependencies',
)
write('pubspec.yaml', pubspec)

# 2) Flutter notification service.
write('lib/core/notifications/notification_service.dart', r'''import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_service.dart';
import '../api/app_user.dart';

const _firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _firebaseSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const _firebaseWebAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
const _firebaseAndroidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
const _firebaseIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
const _firebaseWebVapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

class PushAlert {
  const PushAlert({
    required this.kind,
    required this.title,
    required this.body,
    required this.data,
  });

  final String kind;
  final String title;
  final String body;
  final Map<String, String> data;

  factory PushAlert.fromMessage(RemoteMessage message) {
    final data = message.data.map((key, value) => MapEntry(key, value.toString()));
    return PushAlert(
      kind: data['kind'] ?? 'general',
      title: message.notification?.title ?? data['title'] ?? 'RimbaKawal',
      body: message.notification?.body ?? data['body'] ?? 'Alert baharu diterima.',
      data: data,
    );
  }
}

class PushConfig {
  static bool get hasCommon =>
      _firebaseApiKey.isNotEmpty &&
      _firebaseProjectId.isNotEmpty &&
      _firebaseSenderId.isNotEmpty;

  static bool get isConfigured {
    if (!hasCommon) return false;
    if (kIsWeb) return _firebaseWebAppId.isNotEmpty && _firebaseWebVapidKey.isNotEmpty;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _firebaseAndroidAppId.isNotEmpty;
      case TargetPlatform.iOS:
        return _firebaseIosAppId.isNotEmpty;
      default:
        return false;
    }
  }

  static FirebaseOptions get options {
    final appId = kIsWeb
        ? _firebaseWebAppId
        : defaultTargetPlatform == TargetPlatform.iOS
            ? _firebaseIosAppId
            : _firebaseAndroidAppId;
    return FirebaseOptions(
      apiKey: _firebaseApiKey,
      appId: appId,
      messagingSenderId: _firebaseSenderId,
      projectId: _firebaseProjectId,
    );
  }

  static String get webVapidKey => _firebaseWebVapidKey;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!PushConfig.isConfigured) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: PushConfig.options);
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final StreamController<PushAlert> _foregroundAlerts =
      StreamController<PushAlert>.broadcast();
  Stream<PushAlert> get foregroundAlerts => _foregroundAlerts.stream;

  AppUser? _user;
  String? _token;
  bool _ready = false;
  bool _initializing = false;

  bool get configured => PushConfig.isConfigured;
  bool get ready => _ready;

  Future<void> init() async {
    if (_ready || _initializing || !PushConfig.isConfigured) return;
    _initializing = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: PushConfig.options);
      }
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      }
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onMessage.listen((message) {
        _foregroundAlerts.add(PushAlert.fromMessage(message));
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _foregroundAlerts.add(PushAlert.fromMessage(message));
      });
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _token = token;
        final user = _user;
        if (user != null) unawaited(_registerToken(user, token));
      });
      _ready = true;
    } catch (error) {
      debugPrint('Push notification init skipped: $error');
    } finally {
      _initializing = false;
    }
  }

  Future<bool> bindUser(AppUser user) async {
    _user = user;
    await init();
    if (!_ready) return false;

    if (kIsWeb) {
      try {
        final settings = await FirebaseMessaging.instance.getNotificationSettings();
        if (!_isGranted(settings.authorizationStatus)) return false;
        return _registerCurrentToken(user);
      } catch (_) {
        return false;
      }
    }
    return requestPermissionAndRegister(user);
  }

  Future<bool> requestPermissionAndRegister(AppUser user) async {
    _user = user;
    await init();
    if (!_ready) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      if (!_isGranted(settings.authorizationStatus)) return false;
      return _registerCurrentToken(user);
    } catch (error) {
      debugPrint('Push permission/register failed: $error');
      return false;
    }
  }

  Future<bool> _registerCurrentToken(AppUser user) async {
    try {
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? PushConfig.webVapidKey : null,
        serviceWorkerScriptPath: kIsWeb ? 'firebase-messaging-sw.js' : null,
      );
      if (token == null || token.isEmpty) return false;
      _token = token;
      await _registerToken(user, token);
      return true;
    } catch (error) {
      debugPrint('FCM token registration failed: $error');
      return false;
    }
  }

  Future<void> _registerToken(AppUser user, String token) =>
      ApiService.instance.registerPushDevice(
        token: token,
        platform: _platformName,
      );

  Future<void> unregisterCurrentDevice() async {
    final token = _token;
    if (token != null && token.isNotEmpty) {
      try {
        await ApiService.instance.unregisterPushDevice(token);
      } catch (_) {}
    }
    try {
      if (_ready) await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
    _user = null;
  }

  bool _isGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  String get _platformName {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    return 'android';
  }
}
''')

# 3) Generic foreground alert gate. SOS/session retain their dedicated full-screen alert.
write('lib/core/notifications/notification_alert_gate.dart', r'''import 'dart:async';

import 'package:flutter/material.dart';

import 'notification_service.dart';

class NotificationAlertGate extends StatefulWidget {
  const NotificationAlertGate({required this.child, super.key});
  final Widget child;

  @override
  State<NotificationAlertGate> createState() => _NotificationAlertGateState();
}

class _NotificationAlertGateState extends State<NotificationAlertGate> {
  StreamSubscription<PushAlert>? _subscription;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _subscription = NotificationService.instance.foregroundAlerts.listen(_onAlert);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _onAlert(PushAlert alert) async {
    if (!mounted || _showing) return;
    // Dedicated existing UI already handles these two with louder/full-screen UX.
    if (alert.kind == 'sos' || alert.kind == 'session_start') return;
    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(_icon(alert.kind), size: 48, color: _accent(alert.kind)),
          title: Text(alert.title, textAlign: TextAlign.center),
          content: Text(alert.body, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check_rounded),
              label: const Text('SAYA FAHAM'),
            ),
          ],
        ),
      );
    } finally {
      _showing = false;
    }
  }

  IconData _icon(String kind) => switch (kind) {
        'incident_urgent' => Icons.warning_rounded,
        'incident' => Icons.report_problem_rounded,
        'welfare_attention' => Icons.health_and_safety_rounded,
        'sos_resolved' => Icons.task_alt_rounded,
        _ => Icons.notifications_active_rounded,
      };

  Color _accent(String kind) => switch (kind) {
        'incident_urgent' => const Color(0xFFFF5D66),
        'welfare_attention' => const Color(0xFFFFB142),
        'sos_resolved' => const Color(0xFF55E6C1),
        _ => const Color(0xFFA29BFE),
      };

  @override
  Widget build(BuildContext context) => widget.child;
}
''')

# 4) main.dart initialization + alert gate.
main = read('lib/main.dart')
main = replace_once(
    main,
    "import 'core/nfc/real_nfc_service.dart';\n",
    "import 'core/nfc/real_nfc_service.dart';\nimport 'core/notifications/notification_alert_gate.dart';\nimport 'core/notifications/notification_service.dart';\n",
    'main notification imports',
)
main = replace_once(
    main,
    '  await ApiService.instance.init();\n  await OfflineSyncService.instance.start();\n',
    '  await ApiService.instance.init();\n  await NotificationService.instance.init();\n  await OfflineSyncService.instance.start();\n',
    'notification init',
)
main = replace_once(
    main,
    '''        return SosAlertGate(
          user: user,
          child: DashboardScreen(
            user: user,
            api: _api,
            nfcService: _nfcService,
            mockMode: useMockNfc,
          ),
        );''',
    '''        return NotificationAlertGate(
          child: SosAlertGate(
            user: user,
            child: DashboardScreen(
              user: user,
              api: _api,
              nfcService: _nfcService,
              mockMode: useMockNfc,
            ),
          ),
        );''',
    'notification alert gate',
)
write('lib/main.dart', main)

# 5) ApiService push registration endpoints.
api = read('lib/core/api/api_service.dart')
needle = '''  Future<OfflineBootstrap> getOfflineBootstrap() async {
'''
insert = '''  Future<void> registerPushDevice({
    required String token,
    required String platform,
  }) async {
    _decode(
      await http.post(
        _uri('/api/push/register'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'token': token, 'platform': platform}),
      ),
    );
  }

  Future<void> unregisterPushDevice(String token) async {
    _decode(
      await http.post(
        _uri('/api/push/unregister'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'token': token}),
      ),
    );
  }

'''
api = replace_once(api, needle, insert + needle, 'api push methods')
write('lib/core/api/api_service.dart', api)

# 6) Dashboard: bind native push, manual web permission button, unregister on logout.
dash = read('lib/features/dashboard/dashboard_screen.dart')
dash = replace_once(
    dash,
    "import '../../core/offline/offline_sync_service.dart';\n",
    "import '../../core/offline/offline_sync_service.dart';\nimport '../../core/notifications/notification_service.dart';\n",
    'dashboard notification import',
)
dash = replace_once(
    dash,
    '    unawaited(_refreshPatrolConfig());\n    unawaited(_sync.syncNow());\n',
    '    unawaited(_refreshPatrolConfig());\n    unawaited(NotificationService.instance.bindUser(_user));\n    unawaited(_sync.syncNow());\n',
    'dashboard bind user',
)
logout_old = '''    await _sync.syncNow();
    await widget.api.logout();
'''
logout_new = '''    await _sync.syncNow();
    await NotificationService.instance.unregisterCurrentDevice();
    await widget.api.logout();
'''
dash = replace_once(dash, logout_old, logout_new, 'dashboard logout push unregister')
marker = '''  Future<void> _logout() async {
'''
method = '''  Future<void> _enableNotifications() async {
    final service = NotificationService.instance;
    if (!service.configured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Push notification belum dikonfigurasi pada server aplikasi.'),
        ),
      );
      return;
    }
    final enabled = await service.requestPermissionAndRegister(_user);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Push notification RimbaKawal telah diaktifkan.'
              : 'Kebenaran notification belum diberikan pada peranti/browser ini.',
        ),
      ),
    );
  }

'''
dash = replace_once(dash, marker, method + marker, 'dashboard enable notification method')
appbar_old = '''        actions: [
          IconButton(
            tooltip: 'Alarm / SOS',
'''
appbar_new = '''        actions: [
          IconButton(
            tooltip: 'Aktifkan push notification',
            onPressed: _enableNotifications,
            icon: const Icon(Icons.notifications_active_rounded),
          ),
          IconButton(
            tooltip: 'Alarm / SOS',
'''
dash = replace_once(dash, appbar_old, appbar_new, 'dashboard push action')
# Rebind after profile/user refresh.
refresh_old = '''      setState(() {
        _user = refreshed;
        _sessionIntervalMinutes = refreshed.sessionIntervalMinutes;
      });
      _lastSessionKey = _sessionKey(DateTime.now());
'''
refresh_new = '''      setState(() {
        _user = refreshed;
        _sessionIntervalMinutes = refreshed.sessionIntervalMinutes;
      });
      unawaited(NotificationService.instance.bindUser(refreshed));
      _lastSessionKey = _sessionKey(DateTime.now());
'''
dash = replace_once(dash, refresh_old, refresh_new, 'dashboard refresh rebind')
write('lib/features/dashboard/dashboard_screen.dart', dash)

# 7) Web Firebase Messaging service worker.
write('web/firebase-messaging-sw.js', r'''/* RimbaKawal FCM web background service worker.
 * Values are injected during the production GitHub Actions build.
 */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

const config = {
  apiKey: '__FIREBASE_API_KEY__',
  projectId: '__FIREBASE_PROJECT_ID__',
  messagingSenderId: '__FIREBASE_MESSAGING_SENDER_ID__',
  appId: '__FIREBASE_WEB_APP_ID__',
};

if (Object.values(config).every((value) => value && !value.startsWith('__'))) {
  firebase.initializeApp(config);
  const messaging = firebase.messaging();
  messaging.onBackgroundMessage((payload) => {
    console.debug('[RimbaKawal] background push', payload?.data?.kind || 'general');
  });
}
''')

# 8) Android/iOS notification permissions/capabilities templates.
manifest = read('mobile/android/AndroidManifest.xml')
manifest = replace_once(
    manifest,
    '    <uses-permission android:name="android.permission.INTERNET" />\n',
    '    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n',
    'android notification permission',
)
write('mobile/android/AndroidManifest.xml', manifest)

plist = read('mobile/ios/Info.plist')
plist = replace_once(
    plist,
    '\t<key>UIApplicationSupportsIndirectInputEvents</key>\n\t<true/>\n',
    '\t<key>UIApplicationSupportsIndirectInputEvents</key>\n\t<true/>\n\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>remote-notification</string>\n\t</array>\n',
    'ios background remote notification',
)
write('mobile/ios/Info.plist', plist)

# 9) D1 tables for device tokens + once-only server dispatches.
write('migrations/0010_push_notifications.sql', r'''CREATE TABLE IF NOT EXISTS push_devices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL CHECK (platform IN ('web', 'android', 'ios')),
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_push_devices_user_active
  ON push_devices(user_id, active);

CREATE TABLE IF NOT EXISTS push_dispatch_log (
  dispatch_key TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_push_dispatch_created
  ON push_dispatch_log(created_at);
''')

# 10) Cloudflare FCM sender + session scheduler.
write('worker/push.js', r'''const MALAYSIA_OFFSET_MS = 8 * 60 * 60 * 1000;
let cachedAccessToken = null;
let cachedAccessTokenExpiresAt = 0;

export function pushConfigured(env) {
  return Boolean(
    env.FIREBASE_PROJECT_ID &&
    env.FIREBASE_SERVICE_ACCOUNT_EMAIL &&
    env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY
  );
}

export async function registerPushDevice(env, user, body) {
  const token = String(body?.token ?? '').trim();
  const platform = String(body?.platform ?? '').trim().toLowerCase();
  if (!token || token.length > 4096) throw new Error('Token push tidak sah.');
  if (!['web', 'android', 'ios'].includes(platform)) {
    throw new Error('Platform push tidak sah.');
  }
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO push_devices (user_id, token, platform, active, created_at, updated_at)
     VALUES (?, ?, ?, 1, ?, ?)
     ON CONFLICT(token) DO UPDATE SET
       user_id = excluded.user_id,
       platform = excluded.platform,
       active = 1,
       updated_at = excluded.updated_at`,
  ).bind(user.id, token, platform, now, now).run();
  return { ok: true, configured: pushConfigured(env) };
}

export async function unregisterPushDevice(env, user, body) {
  const token = String(body?.token ?? '').trim();
  if (!token) return { ok: true };
  await env.DB.prepare(
    `UPDATE push_devices SET active = 0, updated_at = ?
     WHERE user_id = ? AND token = ?`,
  ).bind(new Date().toISOString(), user.id, token).run();
  return { ok: true };
}

export async function sendPushToDepartment(
  env,
  departmentId,
  { title, body, kind, data = {}, roles = null, excludeUserId = null },
) {
  if (!pushConfigured(env) || !departmentId) return { sent: 0, configured: false };
  const roleValues = Array.isArray(roles) ? roles.map((role) => String(role).toLowerCase()) : null;
  let sql = `SELECT pd.id, pd.token, pd.user_id
             FROM push_devices pd
             JOIN users u ON u.id = pd.user_id
             WHERE pd.active = 1 AND u.active = 1 AND u.department_id = ?`;
  const binds = [departmentId];
  if (excludeUserId != null) {
    sql += ' AND u.id <> ?';
    binds.push(excludeUserId);
  }
  if (roleValues && roleValues.length > 0) {
    sql += ` AND LOWER(u.jawatan) IN (${roleValues.map(() => '?').join(',')})`;
    binds.push(...roleValues);
  }
  const result = await env.DB.prepare(sql).bind(...binds).all();
  return sendToRows(env, result.results ?? [], { title, body, kind, data });
}

export async function sendPushToUser(env, userId, payload) {
  if (!pushConfigured(env) || !userId) return { sent: 0, configured: false };
  const result = await env.DB.prepare(
    `SELECT id, token, user_id FROM push_devices
     WHERE user_id = ? AND active = 1`,
  ).bind(userId).all();
  return sendToRows(env, result.results ?? [], payload);
}

async function sendToRows(env, rows, payload) {
  if (rows.length === 0) return { sent: 0, configured: true };
  let accessToken;
  try {
    accessToken = await firebaseAccessToken(env);
  } catch (error) {
    console.error('FCM OAuth failed', error);
    return { sent: 0, configured: true };
  }
  let sent = 0;
  for (const row of rows) {
    try {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: row.token,
              notification: { title: payload.title, body: payload.body },
              data: stringifyData({
                ...payload.data,
                kind: payload.kind,
                title: payload.title,
                body: payload.body,
              }),
              android: {
                priority: 'HIGH',
                notification: { sound: 'default' },
              },
              apns: {
                headers: { 'apns-priority': '10' },
                payload: { aps: { sound: 'default' } },
              },
              webpush: {
                headers: { Urgency: 'high' },
                notification: {
                  icon: '/icons/Icon-192.png',
                  badge: '/icons/Icon-192.png',
                },
              },
            },
          }),
        },
      );
      if (response.ok) {
        sent += 1;
        continue;
      }
      const errorText = await response.text();
      if (response.status === 404 || response.status === 400 || errorText.includes('UNREGISTERED')) {
        await env.DB.prepare(
          'UPDATE push_devices SET active = 0, updated_at = ? WHERE id = ?',
        ).bind(new Date().toISOString(), row.id).run();
      }
      console.error('FCM send failed', response.status, errorText.slice(0, 500));
    } catch (error) {
      console.error('FCM device send exception', error);
    }
  }
  return { sent, configured: true };
}

export async function dispatchSessionStartNotifications(env, scheduledAt = new Date()) {
  if (!pushConfigured(env)) return;
  const local = new Date(scheduledAt.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = local.getUTCHours() * 60 + local.getUTCMinutes();
  const departments = await env.DB.prepare(
    `SELECT id, name, session_interval_minutes, session_start_minutes
     FROM departments WHERE active = 1`,
  ).all();

  for (const department of departments.results ?? []) {
    const interval = Math.max(15, Math.min(1440, Number(department.session_interval_minutes || 120)));
    const startMinutes = Math.max(0, Math.min(1439, Number(department.session_start_minutes ?? 420)));
    const relative = (minuteOfDay - startMinutes + 1440) % 1440;
    if (relative % interval !== 0) continue;
    const index = Math.floor(relative / interval);
    const scheduleDate = new Date(local.getTime());
    if (minuteOfDay < startMinutes) scheduleDate.setUTCDate(scheduleDate.getUTCDate() - 1);
    const dayKey = `${scheduleDate.getUTCFullYear()}-${two(scheduleDate.getUTCMonth() + 1)}-${two(scheduleDate.getUTCDate())}`;
    const dispatchKey = `session:${department.id}:${dayKey}:${index}`;
    const inserted = await env.DB.prepare(
      `INSERT OR IGNORE INTO push_dispatch_log (dispatch_key, kind, created_at)
       VALUES (?, 'session_start', ?)`,
    ).bind(dispatchKey, new Date().toISOString()).run();
    if (Number(inserted.meta?.changes || 0) === 0) continue;

    const start = (startMinutes + index * interval) % 1440;
    const end = (start + interval) % 1440;
    await sendPushToDepartment(env, department.id, {
      title: `Sesi Rondaan ${index + 1} Bermula`,
      body: `${department.name} • ${hm(start)}–${hm(end)}. Sila mulakan rondaan dan lengkapkan checkpoint.`,
      kind: 'session_start',
      data: { sessionIndex: index + 1, departmentId: department.id },
      roles: ['patrol', 'supervisor'],
    });
  }

  const cutoff = new Date(Date.now() - 14 * 86400000).toISOString();
  await env.DB.prepare('DELETE FROM push_dispatch_log WHERE created_at < ?').bind(cutoff).run();
}

async function firebaseAccessToken(env) {
  if (cachedAccessToken && Date.now() < cachedAccessTokenExpiresAt - 60000) {
    return cachedAccessToken;
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({ alg: 'RS256', typ: 'JWT' });
  const claim = base64UrlJson({
    iss: env.FIREBASE_SERVICE_ACCOUNT_EMAIL,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  });
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64UrlBytes(new Uint8Array(signature))}`;
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`OAuth ${response.status}: ${(await response.text()).slice(0, 300)}`);
  const json = await response.json();
  cachedAccessToken = json.access_token;
  cachedAccessTokenExpiresAt = Date.now() + Number(json.expires_in || 3600) * 1000;
  return cachedAccessToken;
}

function pemToArrayBuffer(value) {
  const normalized = String(value || '').replace(/\\n/g, '\n');
  const base64 = normalized
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64UrlJson(value) {
  return base64UrlBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function base64UrlBytes(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function stringifyData(data) {
  return Object.fromEntries(
    Object.entries(data || {}).map(([key, value]) => [key, String(value ?? '')]),
  );
}

function two(value) {
  return String(value).padStart(2, '0');
}

function hm(minutes) {
  const normalized = ((minutes % 1440) + 1440) % 1440;
  return `${two(Math.floor(normalized / 60))}:${two(normalized % 60)}`;
}
''')

# 11) Main Worker push routes + cron + SOS resolution notification.
sos = read('worker/sos.js')
sos = replace_once(
    sos,
    "import offlineWorker from './offline.js';\n",
    "import offlineWorker from './offline.js';\nimport { dispatchSessionStartNotifications, pushConfigured, registerPushDevice, sendPushToUser, unregisterPushDevice } from './push.js';\n",
    'sos push import',
)
fetch_marker = '''      if (url.pathname === '/api/sos/alerts' && request.method === 'GET') {
'''
push_routes = '''      if (url.pathname === '/api/push/register' && request.method === 'POST') {
        const auth = await requireUser(request, env);
        if (auth.response) return auth.response;
        try {
          return json(await registerPushDevice(env, auth.user, await readJson(request)));
        } catch (error) {
          return json({ error: error instanceof Error ? error.message : 'Pendaftaran push gagal.' }, 400);
        }
      }
      if (url.pathname === '/api/push/unregister' && request.method === 'POST') {
        const auth = await requireUser(request, env);
        if (auth.response) return auth.response;
        return json(await unregisterPushDevice(env, auth.user, await readJson(request)));
      }
      if (url.pathname === '/api/push/status' && request.method === 'GET') {
        const auth = await requireUser(request, env);
        if (auth.response) return auth.response;
        return json({ configured: pushConfigured(env) });
      }
'''
sos = replace_once(sos, fetch_marker, push_routes + fetch_marker, 'sos push routes')
sos = replace_once(
    sos,
    '''    return offlineWorker.fetch(request, env, ctx);
  },
};''',
    '''    return offlineWorker.fetch(request, env, ctx);
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(dispatchSessionStartNotifications(env, new Date(event.scheduledTime)));
  },
};''',
    'worker scheduled handler',
)
# Expand resolve query to know original SOS user.
sos = replace_once(
    sos,
    '`SELECT id, status, resolved_at, resolution_note\n     FROM sos_events',
    '`SELECT id, user_id, status, resolved_at, resolution_note\n     FROM sos_events',
    'resolve select origin user',
)
resolve_return = '''  return json({
    ok: true,
    event: {
      id: sosId,
      status: 'resolved',
'''
resolve_push = '''  try {
    await sendPushToUser(env, Number(current.user_id), {
      title: 'SOS Telah Diselesaikan',
      body: `SOS anda telah ditandakan selesai oleh ${auth.user.nama}.`,
      kind: 'sos_resolved',
      data: { sosId },
    });
  } catch (error) {
    console.error('SOS resolution push failed', error);
  }

'''
sos = replace_once(sos, resolve_return, resolve_push + resolve_return, 'sos resolution push')
write('worker/sos.js', sos)

# 12) Offline alert fan-out for current local-first events.
offline = read('worker/offline.js')
offline = replace_once(
    offline,
    "import appWorker from './app.js';\n",
    "import appWorker from './app.js';\nimport { sendPushToDepartment } from './push.js';\n",
    'offline push import',
)
# Incident push after images, before return.
incident_return = '''  return { serverId: incidentId, clientEventId };
}

async function syncSos'''
incident_push = '''  try {
    await sendPushToDepartment(env, user.department_id, {
      title: severity === 'urgent' ? 'INSIDEN URGENT' : severity === 'important' ? 'Insiden Penting' : 'Insiden Baru',
      body: `${user.nama} • ${category}: ${note.slice(0, 180)}`,
      kind: severity === 'urgent' ? 'incident_urgent' : 'incident',
      data: { incidentId, severity, category },
      roles: ['management', 'supervisor'],
      excludeUserId: user.id,
    });
  } catch (error) {
    console.error('Incident push failed', error);
  }

  return { serverId: incidentId, clientEventId };
}

async function syncSos'''
offline = replace_once(offline, incident_return, incident_push, 'offline incident push')
sos_return = '''  return { serverId: Number(insert.meta?.last_row_id || 0), clientEventId };
}

async function syncPatrolActivity'''
sos_push = '''  const sosId = Number(insert.meta?.last_row_id || 0);
  try {
    await sendPushToDepartment(env, user.department_id, {
      title: 'SOS RimbaKawal',
      body: `${user.nama} mencetuskan SOS${note ? ` • ${note}` : ''}`.slice(0, 240),
      kind: 'sos',
      data: { sosId },
      excludeUserId: user.id,
    });
  } catch (error) {
    console.error('SOS push failed', error);
  }
  return { serverId: sosId, clientEventId };
}

async function syncPatrolActivity'''
offline = replace_once(offline, sos_return, sos_push, 'offline sos push')
welfare_return = '''  return { serverId: Number(insert.meta?.last_row_id || 0), clientEventId };
}

async function liveStart'''
welfare_push = '''  const welfareId = Number(insert.meta?.last_row_id || 0);
  if (status === 'needs_attention') {
    try {
      await sendPushToDepartment(env, user.department_id, {
        title: 'Welfare Perlu Perhatian',
        body: `${user.nama} memerlukan perhatian${note ? ` • ${note}` : ''}`.slice(0, 240),
        kind: 'welfare_attention',
        data: { welfareId },
        roles: ['management', 'supervisor'],
        excludeUserId: user.id,
      });
    } catch (error) {
      console.error('Welfare push failed', error);
    }
  }
  return { serverId: welfareId, clientEventId };
}

async function liveStart'''
offline = replace_once(offline, welfare_return, welfare_push, 'offline welfare push')
write('worker/offline.js', offline)

# 13) Legacy/direct online endpoints also fan-out alerts.
app = read('worker/app.js')
app = replace_once(
    app,
    "import baseWorker from './index.js';\n",
    "import baseWorker from './index.js';\nimport { sendPushToDepartment } from './push.js';\n",
    'app push import',
)
# Direct incident: insert before return json in createIncident function only.
inc_start = app.index('async function createIncident(request, env) {')
inc_end = app.index('\nasync function getIncidentImages', inc_start)
inc_fn = app[inc_start:inc_end]
inc_needle = '''  return json({
    incident: {
'''
inc_inject = '''  try {
    await sendPushToDepartment(env, auth.user.department_id, {
      title: severity === 'urgent' ? 'INSIDEN URGENT' : severity === 'important' ? 'Insiden Penting' : 'Insiden Baru',
      body: `${auth.user.nama} • ${category}: ${note.slice(0, 180)}`,
      kind: severity === 'urgent' ? 'incident_urgent' : 'incident',
      data: { incidentId, severity, category },
      roles: ['management', 'supervisor'],
      excludeUserId: auth.user.id,
    });
  } catch (error) {
    console.error('Incident push failed', error);
  }

'''
inc_fn = replace_once(inc_fn, inc_needle, inc_inject + inc_needle, 'direct incident push')
app = app[:inc_start] + inc_fn + app[inc_end:]
# Direct SOS: locate function and add before first success return after INSERT.
sos_start = app.find('async function createSos(request, env) {')
if sos_start == -1:
    raise RuntimeError('direct createSos function not found')
next_fn = app.find('\nasync function ', sos_start + 20)
if next_fn == -1:
    next_fn = len(app)
sos_fn = app[sos_start:next_fn]
# Locate result insert variable and success return. Support result or insert naming.
match = re.search(r"const (result|insert) = await env\.DB\.prepare\([\s\S]+?\)\.bind\([\s\S]+?\)\.run\(\);", sos_fn)
if not match:
    raise RuntimeError('direct createSos insert not found')
var_name = match.group(1)
return_pos = sos_fn.find('  return json(', match.end())
if return_pos == -1:
    raise RuntimeError('direct createSos success return not found')
sos_inject = f'''  const pushedSosId = Number({var_name}.meta?.last_row_id || 0);\n  try {{\n    await sendPushToDepartment(env, auth.user.department_id, {{\n      title: 'SOS RimbaKawal',\n      body: `${{auth.user.nama}} mencetuskan SOS${{note ? ` • ${{note}}` : ''}}`.slice(0, 240),\n      kind: 'sos',\n      data: {{ sosId: pushedSosId }},\n      excludeUserId: auth.user.id,\n    }});\n  }} catch (error) {{\n    console.error('SOS push failed', error);\n  }}\n\n'''
sos_fn = sos_fn[:return_pos] + sos_inject + sos_fn[return_pos:]
app = app[:sos_start] + sos_fn + app[next_fn:]
write('worker/app.js', app)

# 14) Wrangler cron trigger every minute for per-department session starts.
wrangler = read('wrangler.jsonc')
wrangler = replace_once(
    wrangler,
    '  "workers_dev": true,\n',
    '  "workers_dev": true,\n  "triggers": {\n    "crons": ["* * * * *"]\n  },\n',
    'wrangler cron',
)
write('wrangler.jsonc', wrangler)

# 15) Deploy workflow: pass public Firebase config to Flutter/SW and optional server secrets to Worker.
deploy = read('.github/workflows/deploy-cloudflare.yml')
deploy = replace_once(
    deploy,
    '''      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
''',
    '''      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
      FIREBASE_API_KEY: ${{ secrets.FIREBASE_API_KEY }}
      FIREBASE_PROJECT_ID: ${{ secrets.FIREBASE_PROJECT_ID }}
      FIREBASE_MESSAGING_SENDER_ID: ${{ secrets.FIREBASE_MESSAGING_SENDER_ID }}
      FIREBASE_WEB_APP_ID: ${{ secrets.FIREBASE_WEB_APP_ID }}
      FIREBASE_ANDROID_APP_ID: ${{ secrets.FIREBASE_ANDROID_APP_ID }}
      FIREBASE_IOS_APP_ID: ${{ secrets.FIREBASE_IOS_APP_ID }}
      FIREBASE_WEB_VAPID_KEY: ${{ secrets.FIREBASE_WEB_VAPID_KEY }}
      FIREBASE_SERVICE_ACCOUNT_EMAIL: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_EMAIL }}
      FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY }}
''',
    'deploy firebase env',
)
deploy = replace_once(
    deploy,
    '      - name: Build Flutter web app\n        run: flutter build web --release --dart-define=USE_MOCK_NFC=true\n',
    '''      - name: Build Flutter web app
        run: >-
          flutter build web --release
          --dart-define=USE_MOCK_NFC=true
          --dart-define=FIREBASE_API_KEY=${{ env.FIREBASE_API_KEY }}
          --dart-define=FIREBASE_PROJECT_ID=${{ env.FIREBASE_PROJECT_ID }}
          --dart-define=FIREBASE_MESSAGING_SENDER_ID=${{ env.FIREBASE_MESSAGING_SENDER_ID }}
          --dart-define=FIREBASE_WEB_APP_ID=${{ env.FIREBASE_WEB_APP_ID }}
          --dart-define=FIREBASE_ANDROID_APP_ID=${{ env.FIREBASE_ANDROID_APP_ID }}
          --dart-define=FIREBASE_IOS_APP_ID=${{ env.FIREBASE_IOS_APP_ID }}
          --dart-define=FIREBASE_WEB_VAPID_KEY=${{ env.FIREBASE_WEB_VAPID_KEY }}

      - name: Configure web push service worker
        shell: bash
        run: |
          node <<'NODE'
          const fs = require('fs');
          const file = 'build/web/firebase-messaging-sw.js';
          if (!fs.existsSync(file)) process.exit(0);
          let text = fs.readFileSync(file, 'utf8');
          const values = {
            FIREBASE_API_KEY: process.env.FIREBASE_API_KEY || '',
            FIREBASE_PROJECT_ID: process.env.FIREBASE_PROJECT_ID || '',
            FIREBASE_MESSAGING_SENDER_ID: process.env.FIREBASE_MESSAGING_SENDER_ID || '',
            FIREBASE_WEB_APP_ID: process.env.FIREBASE_WEB_APP_ID || '',
          };
          for (const [key, value] of Object.entries(values)) {
            text = text.replaceAll(`__${key}__`, value.replaceAll("'", "\\\\'"));
          }
          fs.writeFileSync(file, text);
          NODE
''',
    'deploy web firebase build',
)
secret_step = '''
      - name: Configure Firebase server credentials
        if: ${{ env.FIREBASE_PROJECT_ID != '' && env.FIREBASE_SERVICE_ACCOUNT_EMAIL != '' && env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY != '' }}
        shell: bash
        run: |
          printf '%s' "$FIREBASE_PROJECT_ID" | npx wrangler secret put FIREBASE_PROJECT_ID --config wrangler.deploy.jsonc
          printf '%s' "$FIREBASE_SERVICE_ACCOUNT_EMAIL" | npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_EMAIL --config wrangler.deploy.jsonc
          printf '%s' "$FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY" | npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY --config wrangler.deploy.jsonc
'''
deploy = replace_once(
    deploy,
    '      - name: Apply D1 migrations and seed users\n',
    secret_step + '\n      - name: Apply D1 migrations and seed users\n',
    'deploy worker firebase secrets',
)
write('.github/workflows/deploy-cloudflare.yml', deploy)

# 16) Mobile workflow Firebase client defines.
mobile = read('.github/workflows/build-mobile-production.yml')
mobile = replace_once(
    mobile,
    'env:\n  API_BASE_URL: https://rimbakawal.fscapitalmanagement.workers.dev\n',
    '''env:
  API_BASE_URL: https://rimbakawal.fscapitalmanagement.workers.dev
  FIREBASE_API_KEY: ${{ secrets.FIREBASE_API_KEY }}
  FIREBASE_PROJECT_ID: ${{ secrets.FIREBASE_PROJECT_ID }}
  FIREBASE_MESSAGING_SENDER_ID: ${{ secrets.FIREBASE_MESSAGING_SENDER_ID }}
  FIREBASE_WEB_APP_ID: ${{ secrets.FIREBASE_WEB_APP_ID }}
  FIREBASE_ANDROID_APP_ID: ${{ secrets.FIREBASE_ANDROID_APP_ID }}
  FIREBASE_IOS_APP_ID: ${{ secrets.FIREBASE_IOS_APP_ID }}
  FIREBASE_WEB_VAPID_KEY: ${{ secrets.FIREBASE_WEB_VAPID_KEY }}
''',
    'mobile firebase env',
)
defines = '''          --dart-define=FIREBASE_API_KEY=${{ env.FIREBASE_API_KEY }}
          --dart-define=FIREBASE_PROJECT_ID=${{ env.FIREBASE_PROJECT_ID }}
          --dart-define=FIREBASE_MESSAGING_SENDER_ID=${{ env.FIREBASE_MESSAGING_SENDER_ID }}
          --dart-define=FIREBASE_WEB_APP_ID=${{ env.FIREBASE_WEB_APP_ID }}
          --dart-define=FIREBASE_ANDROID_APP_ID=${{ env.FIREBASE_ANDROID_APP_ID }}
          --dart-define=FIREBASE_IOS_APP_ID=${{ env.FIREBASE_IOS_APP_ID }}
          --dart-define=FIREBASE_WEB_VAPID_KEY=${{ env.FIREBASE_WEB_VAPID_KEY }}'''
# Append after API_BASE_URL in all 3 build commands.
api_line = '          --dart-define=API_BASE_URL=${{ env.API_BASE_URL }}'
count = mobile.count(api_line)
if count != 3:
    raise RuntimeError(f'mobile API define expected 3, got {count}')
mobile = mobile.replace(api_line, api_line + '\n' + defines)
write('.github/workflows/build-mobile-production.yml', mobile)

print('Push notification upgrade applied.')
