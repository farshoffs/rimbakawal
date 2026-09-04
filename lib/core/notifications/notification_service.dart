import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_service.dart';
import '../api/app_user.dart';

const _firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _firebaseSenderId = String.fromEnvironment(
  'FIREBASE_MESSAGING_SENDER_ID',
);
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
    final data = message.data.map(
      (key, value) => MapEntry(key, value.toString()),
    );
    return PushAlert(
      kind: data['kind'] ?? 'general',
      title: message.notification?.title ?? data['title'] ?? 'RimbaKawal',
      body:
          message.notification?.body ??
          data['body'] ??
          'Alert baharu diterima.',
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
    if (!hasCommon) {
      return false;
    }
    if (kIsWeb) {
      return _firebaseWebAppId.isNotEmpty && _firebaseWebVapidKey.isNotEmpty;
    }
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
  bool _sessionRolloverInProgress = false;

  bool get configured => PushConfig.isConfigured;
  bool get ready => _ready;
  bool get sessionRolloverInProgress => _sessionRolloverInProgress;
  String? get currentToken => _token;

  Future<void> init() async {
    if (_ready || _initializing || !PushConfig.isConfigured) {
      return;
    }
    _initializing = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: PushConfig.options);
      }
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      }
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
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
        if (user != null) {
          unawaited(_registerToken(user, token));
        }
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
    if (!_ready) {
      return false;
    }

    bool registered = false;
    if (kIsWeb) {
      try {
        final settings = await FirebaseMessaging.instance
            .getNotificationSettings();
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
    if (!_ready) {
      return false;
    }
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
      if (!_isGranted(settings.authorizationStatus)) {
        return false;
      }
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
      if (token == null || token.isEmpty) {
        return false;
      }
      _token = token;
      await _registerToken(user, token);
      return true;
    } catch (error) {
      debugPrint('FCM token registration failed: $error');
      return false;
    }
  }

  Future<void> _registerToken(AppUser user, String token) => ApiService.instance
      .registerPushDevice(token: token, platform: _platformName);

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
    if (pending == null || _user == null) {
      return;
    }
    _pendingOpenedAlert = null;
    scheduleMicrotask(() => _openedAlerts.add(pending));
  }

  void beginSessionRollover() {
    _sessionRolloverInProgress = true;
  }

  void finishSessionRollover() {
    _sessionRolloverInProgress = false;
  }

  void detachUserKeepPushToken() {
    _user = null;
    _pendingOpenedAlert = null;
  }

  Future<void> unregisterCurrentDevice() async {
    final token = _token;
    if (token != null && token.isNotEmpty) {
      try {
        await ApiService.instance.unregisterPushDevice(token);
      } catch (_) {}
    }
    try {
      if (_ready) {
        await FirebaseMessaging.instance.deleteToken();
      }
    } catch (_) {}
    _token = null;
    _user = null;
  }

  bool _isGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  String get _platformName {
    if (kIsWeb) {
      return 'web';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ios';
    }
    return 'android';
  }
}
