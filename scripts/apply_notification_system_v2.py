from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def write(path, text):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding='utf-8')


def once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)


notification_service = r'''import 'dart:async';

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
  final StreamController<PushAlert> _openedAlerts =
      StreamController<PushAlert>.broadcast();

  Stream<PushAlert> get foregroundAlerts => _foregroundAlerts.stream;
  Stream<PushAlert> get openedAlerts => _openedAlerts.stream;

  AppUser? _user;
  String? _token;
  PushAlert? _pendingOpenedAlert;
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
        _handleOpenedAlert(PushAlert.fromMessage(message));
      });
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _token = token;
        final user = _user;
        if (user != null) unawaited(_registerToken(user, token));
      });
      if (!kIsWeb) {
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) {
          _pendingOpenedAlert = PushAlert.fromMessage(initial);
        }
      }
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

    bool registered = false;
    if (kIsWeb) {
      try {
        final settings = await FirebaseMessaging.instance.getNotificationSettings();
        if (_isGranted(settings.authorizationStatus)) {
          registered = await _registerCurrentToken(user);
        }
      } catch (_) {
        registered = false;
      }
    } else {
      registered = await requestPermissionAndRegister(user);
    }
    _flushPendingOpenedAlert();
    return registered;
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
      return await _registerCurrentToken(user);
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

  void openAlert(PushAlert alert) {
    if (_user == null) {
      _pendingOpenedAlert = alert;
      return;
    }
    _openedAlerts.add(alert);
  }

  void _handleOpenedAlert(PushAlert alert) {
    if (_user == null) {
      _pendingOpenedAlert = alert;
      return;
    }
    _openedAlerts.add(alert);
  }

  void _flushPendingOpenedAlert() {
    final pending = _pendingOpenedAlert;
    if (pending == null || _user == null) return;
    _pendingOpenedAlert = null;
    scheduleMicrotask(() => _openedAlerts.add(pending));
  }

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
'''
write('lib/core/notifications/notification_service.dart', notification_service)

notification_gate = r'''import 'dart:async';

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
    // SOS has a dedicated full-screen alarm/polling experience.
    if (alert.kind == 'sos') return;
    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF222636),
          icon: Icon(_icon(alert.kind), size: 48, color: _accent(alert.kind)),
          title: Text(
            alert.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            alert.body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('TUTUP'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                NotificationService.instance.openAlert(alert);
              },
              icon: Icon(_openIcon(alert.kind)),
              label: Text(_openLabel(alert.kind)),
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
        'session_start' => Icons.directions_walk_rounded,
        'patrol_not_started' => Icons.timer_off_rounded,
        'session_ending' => Icons.timer_rounded,
        'session_missed' || 'session_incomplete' => Icons.event_busy_rounded,
        'checkpoint_scanned' => Icons.nfc_rounded,
        'patrol_completed' => Icons.verified_rounded,
        'patrol_ended' => Icons.flag_rounded,
        'attendance_punch' => Icons.fingerprint_rounded,
        'attendance_review' => Icons.face_retouching_natural_rounded,
        _ => Icons.notifications_active_rounded,
      };

  Color _accent(String kind) => switch (kind) {
        'incident_urgent' || 'session_missed' => const Color(0xFFFF5D66),
        'welfare_attention' || 'session_ending' || 'attendance_review' =>
          const Color(0xFFFFB142),
        'sos_resolved' || 'patrol_completed' || 'attendance_punch' =>
          const Color(0xFF55E6C1),
        _ => const Color(0xFFA29BFE),
      };

  IconData _openIcon(String kind) => switch (kind) {
        'session_start' || 'patrol_not_started' || 'session_ending' =>
          Icons.directions_walk_rounded,
        'attendance_punch' || 'attendance_review' => Icons.fingerprint_rounded,
        _ => Icons.open_in_new_rounded,
      };

  String _openLabel(String kind) => switch (kind) {
        'session_start' || 'patrol_not_started' || 'session_ending' =>
          'MULA RONDAAN',
        _ => 'BUKA',
      };

  @override
  Widget build(BuildContext context) => widget.child;
}
'''
write('lib/core/notifications/notification_alert_gate.dart', notification_gate)

# Manual login must use the same notification gate as restored sessions.
p = 'lib/features/auth/login_screen.dart'
t = read(p)
t = once(
    t,
    "import '../../core/nfc/nfc_service.dart';\nimport '../dashboard/dashboard_screen.dart';",
    "import '../../core/nfc/nfc_service.dart';\nimport '../../core/notifications/notification_alert_gate.dart';\nimport '../dashboard/dashboard_screen.dart';",
    'login notification import',
)
t = once(
    t,
    '''          builder: (_) => SosAlertGate(\n            user: user,\n            child: DashboardScreen(\n              user: user,\n              api: _api,\n              nfcService: widget.nfcService,\n              mockMode: widget.mockMode,\n            ),\n          ),''',
    '''          builder: (_) => NotificationAlertGate(\n            child: SosAlertGate(\n              user: user,\n              child: DashboardScreen(\n                user: user,\n                api: _api,\n                nfcService: widget.nfcService,\n                mockMode: widget.mockMode,\n              ),\n            ),\n          ),''',
    'login notification gate',
)
write(p, t)

# Dashboard becomes the single deep-link router for opened notifications.
p = 'lib/features/dashboard/dashboard_screen.dart'
t = read(p)
t = once(
    t,
    "import '../admin/admin_screen.dart';\nimport '../admin/command_center_screen.dart';",
    "import '../admin/admin_screen.dart';\nimport '../admin/attendance_history_screen.dart';\nimport '../admin/command_center_screen.dart';\nimport '../admin/sos_management_screen.dart';",
    'dashboard notification target imports',
)
t = once(
    t,
    '''  Timer? _sessionTimer;\n  Timer? _configTimer;\n  String? _lastSessionKey;\n  bool _forcingRelogin = false;''',
    '''  Timer? _sessionTimer;\n  Timer? _configTimer;\n  StreamSubscription<PushAlert>? _openedPushSubscription;\n  String? _lastSessionKey;\n  bool _forcingRelogin = false;''',
    'dashboard push subscription field',
)
t = once(
    t,
    '''    unawaited(_refreshPatrolConfig());\n    unawaited(NotificationService.instance.bindUser(_user));\n    unawaited(_sync.syncNow());''',
    '''    _openedPushSubscription = NotificationService.instance.openedAlerts.listen(\n      _openPushTarget,\n    );\n    unawaited(_refreshPatrolConfig());\n    unawaited(_bindNotifications(_user));\n    unawaited(_sync.syncNow());''',
    'dashboard bind notifications',
)
t = once(
    t,
    '''    _sessionTimer?.cancel();\n    _configTimer?.cancel();\n    super.dispose();''',
    '''    _sessionTimer?.cancel();\n    _configTimer?.cancel();\n    _openedPushSubscription?.cancel();\n    super.dispose();''',
    'dashboard dispose push subscription',
)
insert_before = '''  Future<void> _enableNotifications() async {'''
router = r'''  Future<void> _bindNotifications(AppUser user) async {
    await NotificationService.instance.bindUser(user);
  }

  DateTime? _pushDate(PushAlert alert) {
    for (final key in const ['workDate', 'sessionDate', 'date']) {
      final value = alert.data[key];
      if (value == null || value.isEmpty) continue;
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  void _returnToDashboard() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openPushTarget(PushAlert alert) {
    if (!mounted) return;
    final date = _pushDate(alert);
    switch (alert.kind) {
      case 'session_start':
      case 'patrol_not_started':
      case 'session_ending':
      case 'checkpoint_scanned':
        _openPatrol();
      case 'session_missed':
      case 'session_incomplete':
        _open(
          ClockingHistoryScreen(
            api: widget.api,
            user: _user,
            initialDate: date,
            initialDepartmentId: _user.departmentId,
            initialFilter: 'missed',
          ),
        );
      case 'patrol_completed':
      case 'patrol_ended':
        _open(
          ClockingHistoryScreen(
            api: widget.api,
            user: _user,
            initialDate: date,
            initialDepartmentId: _user.departmentId,
          ),
        );
      case 'attendance_punch':
        _open(AttendanceScreen(api: widget.api, user: _user));
      case 'attendance_review':
        if (_user.canMonitor) {
          _open(AttendanceHistoryScreen(api: widget.api, initialDate: date));
        } else {
          _returnToDashboard();
        }
      case 'incident':
      case 'incident_urgent':
      case 'welfare_attention':
        if (_user.canMonitor) {
          _open(CommandCenterScreen(api: widget.api));
        } else {
          _returnToDashboard();
        }
      case 'sos':
        if (_user.canMonitor) {
          _open(const SosManagementScreen());
        } else {
          _returnToDashboard();
        }
      case 'sos_resolved':
      default:
        _returnToDashboard();
    }
  }

'''
if insert_before not in t:
    raise SystemExit('dashboard enable notification marker missing')
t = t.replace(insert_before, router + insert_before, 1)
t = once(
    t,
    '      unawaited(NotificationService.instance.bindUser(refreshed));',
    '      unawaited(_bindNotifications(refreshed));',
    'dashboard refreshed user push bind',
)
write(p, t)

# Replace the scheduler with richer operational reminders while retaining the existing export name.
push = r'''const MALAYSIA_OFFSET_MS = 8 * 60 * 60 * 1000;
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
  const departments = await env.DB.prepare(
    `SELECT id, name, session_interval_minutes, session_start_minutes
     FROM departments WHERE active = 1`,
  ).all();

  for (const department of departments.results ?? []) {
    const interval = Math.max(15, Math.min(1440, Number(department.session_interval_minutes || 120)));
    const startMinutes = Math.max(0, Math.min(1439, Number(department.session_start_minutes ?? 420)));
    const window = sessionWindowAt(scheduledAt, interval, startMinutes);
    const durationMinutes = Math.max(1, Math.round((window.end.getTime() - window.start.getTime()) / 60000));
    const minuteIntoSession = Math.max(0, Math.floor((scheduledAt.getTime() - window.start.getTime()) / 60000));
    const commonData = {
      sessionIndex: window.index + 1,
      sessionDate: malaysiaDateKey(window.start),
      departmentId: department.id,
    };

    if (minuteIntoSession === 0) {
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

    const notStartedMinute = Math.min(15, Math.max(5, Math.floor(durationMinutes / 4)));
    if (minuteIntoSession === notStartedMinute) {
      await dispatchNotStarted(env, department, window);
    }

    const warningLead = Math.max(2, Math.min(15, Math.floor(durationMinutes / 4)));
    const warningMinute = durationMinutes - warningLead;
    if (warningMinute > 0 && minuteIntoSession === warningMinute) {
      await dispatchEndingSoon(env, department, window, warningLead);
    }
  }

  const cutoff = new Date(Date.now() - 14 * 86400000).toISOString();
  await env.DB.prepare('DELETE FROM push_dispatch_log WHERE created_at < ?').bind(cutoff).run();
}

async function dispatchNotStarted(env, department, window) {
  const total = await checkpointTotal(env, department.id);
  if (total <= 0) return;
  const users = await patrolUsersWithProgress(env, department.id, window.start, window.end);
  for (const user of users) {
    if (user.started || user.scanCount > 0) continue;
    const key = `not-started:${department.id}:${window.dayKey}:${window.index}:${user.id}`;
    if (!await claimDispatch(env, key, 'patrol_not_started')) continue;
    await sendPushToUser(env, user.id, {
      title: 'Rondaan Belum Dimulakan',
      body: `Sesi Rondaan ${window.index + 1} sedang berjalan. Anda belum merekod sebarang checkpoint.`,
      kind: 'patrol_not_started',
      data: {
        sessionIndex: window.index + 1,
        sessionDate: malaysiaDateKey(window.start),
        departmentId: department.id,
      },
    });
  }
}

async function dispatchEndingSoon(env, department, window, warningLead) {
  const total = await checkpointTotal(env, department.id);
  if (total <= 0) return;
  const users = await patrolUsersWithProgress(env, department.id, window.start, window.end);
  for (const user of users) {
    if (user.scanCount >= total) continue;
    const key = `ending:${department.id}:${window.dayKey}:${window.index}:${user.id}`;
    if (!await claimDispatch(env, key, 'session_ending')) continue;
    await sendPushToUser(env, user.id, {
      title: `Sesi Hampir Tamat • ${warningLead} minit`,
      body: `${user.scanCount}/${total} checkpoint direkod. Lengkapkan baki checkpoint sebelum sesi tamat.`,
      kind: 'session_ending',
      data: {
        sessionIndex: window.index + 1,
        sessionDate: malaysiaDateKey(window.start),
        departmentId: department.id,
        scanned: user.scanCount,
        total,
      },
    });
  }
}

async function dispatchPreviousOutcome(env, department, window) {
  const total = await checkpointTotal(env, department.id);
  if (total <= 0) return;
  const users = await patrolUsersWithProgress(env, department.id, window.start, window.end);
  let missed = 0;
  let incomplete = 0;
  for (const user of users) {
    if (user.scanCount >= total) continue;
    const kind = user.scanCount === 0 ? 'session_missed' : 'session_incomplete';
    if (kind === 'session_missed') missed += 1;
    else incomplete += 1;
    const key = `outcome:${department.id}:${window.dayKey}:${window.index}:${user.id}`;
    if (!await claimDispatch(env, key, kind)) continue;
    await sendPushToUser(env, user.id, {
      title: kind === 'session_missed' ? 'Sesi Rondaan Terlepas' : 'Sesi Rondaan Tidak Lengkap',
      body: `${user.scanCount}/${total} checkpoint direkod sebelum sesi tamat.`,
      kind,
      data: {
        sessionIndex: window.index + 1,
        sessionDate: malaysiaDateKey(window.start),
        departmentId: department.id,
        scanned: user.scanCount,
        total,
      },
    });
  }

  if (missed + incomplete > 0) {
    const key = `outcome-admin:${department.id}:${window.dayKey}:${window.index}`;
    if (await claimDispatch(env, key, 'session_outcome_summary')) {
      await sendPushToDepartment(env, department.id, {
        title: 'Ringkasan Sesi Rondaan',
        body: `${missed} terlepas • ${incomplete} tidak lengkap bagi sesi yang baru tamat.`,
        kind: 'session_incomplete',
        data: {
          sessionIndex: window.index + 1,
          sessionDate: malaysiaDateKey(window.start),
          departmentId: department.id,
          missed,
          incomplete,
        },
        roles: ['management', 'supervisor'],
      });
    }
  }
}

async function autoCloseExpiredLivePatrols(env, departmentId, currentStart) {
  const stale = await env.DB.prepare(
    `SELECT user_id, client_session_id
     FROM live_patrol_presence
     WHERE department_id = ? AND active = 1 AND started_at < ?`,
  ).bind(departmentId, currentStart.toISOString()).all();
  const endedAt = currentStart.toISOString();
  for (const row of stale.results ?? []) {
    await env.DB.prepare(
      `UPDATE live_patrol_presence
       SET active = 0, ended_at = ?, updated_at = ?
       WHERE user_id = ? AND client_session_id = ? AND active = 1`,
    ).bind(endedAt, endedAt, row.user_id, row.client_session_id).run();
    await env.DB.prepare(
      `UPDATE patrol_session_history
       SET ended_at = COALESCE(ended_at, ?), updated_at = ?
       WHERE user_id = ? AND client_session_id = ?`,
    ).bind(endedAt, endedAt, row.user_id, row.client_session_id).run();
  }
}

async function patrolUsersWithProgress(env, departmentId, start, end) {
  const result = await env.DB.prepare(
    `SELECT u.id, u.nama,
            COUNT(DISTINCT n.checkpoint_id) AS scan_count,
            CASE WHEN EXISTS (
              SELECT 1 FROM patrol_session_history p
              WHERE p.user_id = u.id
                AND p.started_at >= ? AND p.started_at < ?
            ) THEN 1 ELSE 0 END AS started
     FROM users u
     LEFT JOIN nfc_scans n
       ON n.user_id = u.id
      AND n.scanned_at >= ? AND n.scanned_at < ?
      AND n.checkpoint_id IS NOT NULL
     WHERE u.department_id = ? AND u.active = 1
       AND LOWER(u.jawatan) IN ('patrol', 'supervisor')
     GROUP BY u.id, u.nama
     ORDER BY u.id`,
  ).bind(
    start.toISOString(),
    end.toISOString(),
    start.toISOString(),
    end.toISOString(),
    departmentId,
  ).all();
  return (result.results ?? []).map((row) => ({
    id: Number(row.id),
    nama: row.nama,
    scanCount: Number(row.scan_count || 0),
    started: Number(row.started || 0) === 1,
  }));
}

async function checkpointTotal(env, departmentId) {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS total FROM checkpoints
     WHERE department_id = ? AND active = 1`,
  ).bind(departmentId).first();
  return Number(row?.total || 0);
}

async function claimDispatch(env, key, kind) {
  const inserted = await env.DB.prepare(
    `INSERT OR IGNORE INTO push_dispatch_log (dispatch_key, kind, created_at)
     VALUES (?, ?, ?)`,
  ).bind(key, kind, new Date().toISOString()).run();
  return Number(inserted.meta?.changes || 0) > 0;
}

function sessionWindowAt(value, interval, startMinutes) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  const minuteOfDay = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  const localMidnightUtc = Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate(),
  );
  let dayStartMs = localMidnightUtc - MALAYSIA_OFFSET_MS + startMinutes * 60000;
  if (minuteOfDay < startMinutes) dayStartMs -= 86400000;
  const index = Math.max(0, Math.floor((value.getTime() - dayStartMs) / (interval * 60000)));
  const startMs = dayStartMs + index * interval * 60000;
  const endMs = Math.min(dayStartMs + 86400000, startMs + interval * 60000);
  const dayLocal = new Date(dayStartMs + MALAYSIA_OFFSET_MS);
  const dayKey = `${dayLocal.getUTCFullYear()}-${two(dayLocal.getUTCMonth() + 1)}-${two(dayLocal.getUTCDate())}`;
  return { index, dayKey, start: new Date(startMs), end: new Date(endMs) };
}

function malaysiaDateKey(value) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  return `${shifted.getUTCFullYear()}-${two(shifted.getUTCMonth() + 1)}-${two(shifted.getUTCDate())}`;
}

function hmFromDate(value) {
  const shifted = new Date(value.getTime() + MALAYSIA_OFFSET_MS);
  return `${two(shifted.getUTCHours())}:${two(shifted.getUTCMinutes())}`;
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
'''
write('worker/push.js', push)

# Checkpoint and patrol completion confirmation pushes.
p = 'worker/offline.js'
t = read(p)
t = once(
    t,
    "import { sendPushToDepartment } from './push.js';",
    "import { sendPushToDepartment, sendPushToUser } from './push.js';",
    'offline push import',
)
scan_return = '''  return {\n    serverId: Number(insert.meta?.last_row_id || 0),\n    clientEventId,\n    checkpointId: Number(checkpoint.id),\n    checkpointName: checkpoint.name,\n    sessionIndex,\n    clientSessionId: clientSessionId || null,\n  };'''
scan_push = r'''  try {
    const totalRow = await env.DB.prepare(
      `SELECT COUNT(*) AS total FROM checkpoints
       WHERE department_id = ? AND active = 1`,
    ).bind(user.department_id).first();
    const countRow = clientSessionId
      ? await env.DB.prepare(
        `SELECT COUNT(DISTINCT checkpoint_id) AS total FROM nfc_scans
         WHERE user_id = ? AND client_session_id = ? AND checkpoint_id IS NOT NULL`,
      ).bind(user.id, clientSessionId).first()
      : await env.DB.prepare(
        `SELECT COUNT(DISTINCT checkpoint_id) AS total FROM nfc_scans
         WHERE user_id = ? AND scanned_at >= ? AND scanned_at < ? AND checkpoint_id IS NOT NULL`,
      ).bind(user.id, startIso, endIso).first();
    const total = Number(totalRow?.total || 0);
    const scanned = Number(countRow?.total || 0);
    await sendPushToUser(env, user.id, {
      title: 'Checkpoint Direkod',
      body: `${checkpoint.name} • ${scanned}/${total} checkpoint sesi ini.`,
      kind: 'checkpoint_scanned',
      data: {
        checkpointId: Number(checkpoint.id),
        clientSessionId: clientSessionId || '',
        sessionIndex: sessionIndex + 1,
        sessionDate: malaysiaDateKey(occurredAt),
        scanned,
        total,
      },
    });
  } catch (error) {
    console.error('Checkpoint confirmation push failed', error);
  }

''' + scan_return
if scan_return not in t:
    raise SystemExit('offline scan return marker missing')
t = t.replace(scan_return, scan_push, 1)
patrol_return = '''  return { serverId: Number(insert.meta?.last_row_id || 0), clientEventId };\n}\n\nasync function syncWelfareCheck'''
patrol_push = r'''  if (type === 'patrol_end') {
    try {
      const totalRow = await env.DB.prepare(
        `SELECT COUNT(*) AS total FROM checkpoints
         WHERE department_id = ? AND active = 1`,
      ).bind(user.department_id).first();
      const scanRow = await env.DB.prepare(
        `SELECT COUNT(DISTINCT checkpoint_id) AS total FROM nfc_scans
         WHERE user_id = ? AND client_session_id = ? AND checkpoint_id IS NOT NULL`,
      ).bind(user.id, clientSessionId).first();
      const total = Number(totalRow?.total || 0);
      const scanned = Number(scanRow?.total || 0);
      const complete = total > 0 && scanned >= total;
      await sendPushToUser(env, user.id, {
        title: complete ? 'Rondaan Selesai' : 'Rondaan Ditamatkan',
        body: complete
          ? `Semua ${total} checkpoint telah lengkap.`
          : `${scanned}/${total} checkpoint direkod sebelum rondaan ditamatkan.`,
        kind: complete ? 'patrol_completed' : 'patrol_ended',
        data: {
          clientSessionId,
          sessionDate: malaysiaDateKey(occurredAt),
          scanned,
          total,
        },
      });
    } catch (error) {
      console.error('Patrol completion push failed', error);
    }
  }

  return { serverId: Number(insert.meta?.last_row_id || 0), clientEventId };
}

async function syncWelfareCheck'''
if patrol_return not in t:
    raise SystemExit('offline patrol return marker missing')
t = t.replace(patrol_return, patrol_push, 1)
write(p, t)

# Attendance confirmations + review alerts.
p = 'worker/attendance.js'
t = read(p)
t = once(
    t,
    "import sosWorker from './sos.js';",
    "import sosWorker from './sos.js';\nimport { sendPushToDepartment, sendPushToUser } from './push.js';",
    'attendance push imports',
)
marker = '''  return json({\n    record: {\n      id: Number(insert.meta?.last_row_id || 0),'''
attendance_push = r'''  const attendanceId = Number(insert.meta?.last_row_id || 0);
  try {
    await sendPushToUser(env, auth.user.id, {
      title: punchType === 'IN' ? 'Kehadiran Masuk Direkod' : 'Kehadiran Keluar Direkod',
      body: `${department.name} • ${punchType} berjaya direkod.`,
      kind: 'attendance_punch',
      data: { attendanceId, workDate, punchType },
    });
    if (face.status !== 'matched') {
      await sendPushToDepartment(env, auth.user.department_id, {
        title: 'Kehadiran Perlu Semakan Wajah',
        body: `${auth.user.nama} • ${punchType} memerlukan semakan wajah (${face.status}).`,
        kind: 'attendance_review',
        data: { attendanceId, workDate, punchType, faceStatus: face.status },
        roles: ['management', 'supervisor'],
        excludeUserId: auth.user.id,
      });
    }
  } catch (error) {
    console.error('Attendance push failed', error);
  }

  return json({
    record: {
      id: attendanceId,'''
if marker not in t:
    raise SystemExit('attendance return marker missing')
t = t.replace(marker, attendance_push, 1)
write(p, t)

# iOS APNs is prepared, not activated. The active Runner.entitlements remains NFC-only.
write('mobile/ios/APNS_ENTITLEMENT_TEMPLATE.plist', r'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>aps-environment</key>
  <string>development</string>
</dict>
</plist>
''')
write('docs/IOS_PUSH_PREPARATION.md', r'''# RimbaKawal iOS Push Preparation

The Flutter/Firebase Messaging client is already prepared to receive and deep-link push notifications, but APNs is intentionally **not activated yet** because an Apple Developer Program membership is required for production signing/capabilities.

When the Apple Developer Program account is ready:

1. Enable **Push Notifications** for the RimbaKawal App ID in Apple Developer.
2. Create an APNs Auth Key (`.p8`) or configure the appropriate APNs certificate.
3. Upload the APNs key/certificate to the RimbaKawal iOS app in Firebase Console.
4. Add the `aps-environment` entitlement to `mobile/ios/Runner.entitlements` while preserving the existing NFC entitlement. Use `mobile/ios/APNS_ENTITLEMENT_TEMPLATE.plist` only as a reference fragment.
5. Sign/provision the iOS build with a profile that includes Push Notifications and NFC.
6. Test foreground, background, and terminated-state notification opening on a physical iPhone.

Do not copy the template over `Runner.entitlements`; merge the APNs key into the existing entitlement file.
''')

# Version bump for the production rebuild.
p = 'pubspec.yaml'
t = read(p)
t = once(t, 'version: 0.5.11+27', 'version: 0.5.12+28', 'version bump')
write(p, t)

print('Notification system v2 patch applied.')
