import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../api/app_user.dart';
import 'offline_models.dart';

class OfflineStore extends ChangeNotifier {
  OfflineStore._();

  static final OfflineStore instance = OfflineStore._();

  static const _eventsBoxName = 'rimbakawal_field_events_v2';
  static const _cacheBoxName = 'rimbakawal_field_cache_v2';
  static const _cachedUserKey = 'cached_user';
  static const _bootstrapKey = 'patrol_bootstrap';
  static const _nfcModeKey = 'nfc_operation_mode';
  static const _activePatrolKeyPrefix = 'active_patrol_';
  static const _httpCachePrefix = 'http_cache_v1:';
  static const _httpCacheMaxEntries = 250;
  static const _httpCacheMaxCharacters = 20 * 1024 * 1024;

  late Box<dynamic> _eventsBox;
  late Box<dynamic> _cacheBox;
  bool _ready = false;
  final Random _random = Random.secure();

  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    await Hive.initFlutter();
    _eventsBox = await Hive.openBox<dynamic>(_eventsBoxName);
    _cacheBox = await Hive.openBox<dynamic>(_cacheBoxName);
    _ready = true;
    await purgeSyncedOlderThan(const Duration(days: 14));
    await purgeHttpCacheOlderThan(const Duration(days: 90));
    await trimHttpCache();
    notifyListeners();
  }

  String newId(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = _random.nextInt(0x7fffffff).toRadixString(16);
    return '$prefix-$now-$random';
  }

  Map<String, dynamic>? activePatrol(int userId) {
    if (!_ready) return null;
    final value = _cacheBox.get('$_activePatrolKeyPrefix$userId');
    if (value is! Map) return null;
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActivePatrol({
    required int userId,
    required String clientSessionId,
    required DateTime startedAt,
    required int sessionIndex,
    required String dayKey,
  }) async {
    _ensureReady();
    await _cacheBox.put('$_activePatrolKeyPrefix$userId', {
      'clientSessionId': clientSessionId,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'sessionIndex': sessionIndex,
      'dayKey': dayKey,
    });
    notifyListeners();
  }

  Future<void> clearActivePatrol(int userId, {String? clientSessionId}) async {
    if (!_ready) return;
    final key = '$_activePatrolKeyPrefix$userId';
    if (clientSessionId != null) {
      final current = activePatrol(userId);
      if (current != null && current['clientSessionId'] != clientSessionId) {
        return;
      }
    }
    await _cacheBox.delete(key);
    notifyListeners();
  }

  Future<OfflineEvent> queueEvent({
    required int userId,
    required String type,
    required Map<String, dynamic> payload,
    DateTime? occurredAt,
    Map<String, dynamic>? location,
    String? id,
  }) async {
    _ensureReady();
    final event = OfflineEvent(
      id: id ?? newId(type),
      userId: userId,
      type: type,
      occurredAt: occurredAt ?? DateTime.now(),
      payload: payload,
      location: location,
      status: 'pending',
      attempts: 0,
    );
    await _eventsBox.put(event.id, event.toJson());
    notifyListeners();
    return event;
  }

  List<OfflineEvent> eventsForUser(int userId, {int limit = 250}) {
    if (!_ready) return const [];
    final rows = <OfflineEvent>[];
    for (final value in _eventsBox.values) {
      if (value is! Map) continue;
      try {
        final event = OfflineEvent.fromJson(Map<String, dynamic>.from(value));
        if (event.userId == userId) rows.add(event);
      } catch (_) {}
    }
    rows.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return rows.take(limit).toList(growable: false);
  }

  List<OfflineEvent> pendingEvents(int userId, {int limit = 50}) {
    final rows = eventsForUser(
      userId,
      limit: 1000,
    ).where((event) => event.isPending).toList();
    rows.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return rows.take(limit).toList(growable: false);
  }

  int pendingCount(int userId) => eventsForUser(
    userId,
    limit: 1000,
  ).where((event) => event.isPending).length;

  int failedCount(int userId) => eventsForUser(
    userId,
    limit: 1000,
  ).where((event) => event.isFailed).length;

  int syncedCount(int userId) => eventsForUser(
    userId,
    limit: 1000,
  ).where((event) => event.isSynced).length;

  Future<void> markAttempt(String id, {String? error}) async {
    final event = _event(id);
    if (event == null) return;
    await _eventsBox.put(
      id,
      event
          .copyWith(
            status: 'pending',
            attempts: event.attempts + 1,
            lastError: error,
          )
          .toJson(),
    );
    notifyListeners();
  }

  Future<void> markSynced(String id) async {
    final event = _event(id);
    if (event == null) return;
    if (event.type == 'attendance' || event.type == 'incident') {
      await _eventsBox.delete(id);
      notifyListeners();
      return;
    }
    await _eventsBox.put(
      id,
      event
          .copyWith(
            status: 'synced',
            attempts: event.attempts + 1,
            clearError: true,
            syncedAt: DateTime.now(),
          )
          .toJson(),
    );
    notifyListeners();
  }

  Future<void> markFailed(String id, String error) async {
    final event = _event(id);
    if (event == null) return;
    await _eventsBox.put(
      id,
      event
          .copyWith(
            status: 'failed',
            attempts: event.attempts + 1,
            lastError: error,
          )
          .toJson(),
    );
    notifyListeners();
  }

  Future<void> retryFailed(int userId) async {
    for (final event in eventsForUser(userId, limit: 1000)) {
      if (!event.isFailed) continue;
      await _eventsBox.put(
        event.id,
        event.copyWith(status: 'pending', clearError: true).toJson(),
      );
    }
    notifyListeners();
  }

  Future<void> cacheUser(AppUser user) async {
    _ensureReady();
    await _cacheBox.put(_cachedUserKey, _userToJson(user));
    notifyListeners();
  }

  AppUser? cachedUser() {
    if (!_ready) return null;
    final value = _cacheBox.get(_cachedUserKey);
    if (value is! Map) return null;
    try {
      return AppUser.fromJson(Map<String, dynamic>.from(value));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCachedUser() async {
    if (!_ready) return;
    await _cacheBox.delete(_cachedUserKey);
    notifyListeners();
  }

  Future<void> cacheBootstrap(OfflineBootstrap bootstrap) async {
    _ensureReady();
    await _cacheBox.put(_bootstrapKey, bootstrap.toJson());
    notifyListeners();
  }

  OfflineBootstrap? cachedBootstrap() {
    if (!_ready) return null;
    final value = _cacheBox.get(_bootstrapKey);
    if (value is! Map) return null;
    try {
      return OfflineBootstrap.fromJson(Map<String, dynamic>.from(value));
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheHttpResponse(
    String key,
    String body, {
    int statusCode = 200,
  }) async {
    if (!_ready) return;
    if (body.length > 2 * 1024 * 1024) return;
    final scopedKey = _scopedHttpKey(key);
    await _cacheBox.put(scopedKey, {
      'body': body,
      'statusCode': statusCode,
      'storedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await trimHttpCache();
  }

  Map<String, dynamic>? cachedHttpResponse(String key) {
    if (!_ready) return null;
    final value = _cacheBox.get(_scopedHttpKey(key));
    if (value is! Map) return null;
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> purgeHttpCacheOlderThan(Duration age) async {
    if (!_ready) return;
    final cutoff = DateTime.now().toUtc().subtract(age);
    final keys = <dynamic>[];
    for (final key in _cacheBox.keys) {
      if (key is! String || !key.startsWith(_httpCachePrefix)) continue;
      final value = _cacheBox.get(key);
      if (value is! Map) {
        keys.add(key);
        continue;
      }
      final storedAt = DateTime.tryParse(value['storedAt'] as String? ?? '');
      if (storedAt == null || storedAt.isBefore(cutoff)) keys.add(key);
    }
    if (keys.isNotEmpty) await _cacheBox.deleteAll(keys);
  }

  Future<void> trimHttpCache() async {
    if (!_ready) return;
    final entries = <MapEntry<dynamic, Map<String, dynamic>>>[];
    for (final key in _cacheBox.keys) {
      if (key is! String || !key.startsWith(_httpCachePrefix)) continue;
      final value = _cacheBox.get(key);
      if (value is! Map) continue;
      entries.add(MapEntry(key, Map<String, dynamic>.from(value)));
    }
    entries.sort((a, b) {
      final aDate =
          DateTime.tryParse(a.value['storedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final bDate =
          DateTime.tryParse(b.value['storedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return aDate.compareTo(bDate);
    });
    var characters = entries.fold<int>(
      0,
      (sum, item) => sum + (item.value['body'] as String? ?? '').length,
    );
    final keysToDelete = <dynamic>[];
    while (entries.length - keysToDelete.length > _httpCacheMaxEntries ||
        characters > _httpCacheMaxCharacters) {
      final index = keysToDelete.length;
      if (index >= entries.length) break;
      final item = entries[index];
      keysToDelete.add(item.key);
      characters -= (item.value['body'] as String? ?? '').length;
    }
    if (keysToDelete.isNotEmpty) await _cacheBox.deleteAll(keysToDelete);
  }

  String _scopedHttpKey(String key) {
    final userId = cachedUser()?.id ?? 0;
    return '$_httpCachePrefix$userId::$key';
  }

  String get nfcMode {
    if (!_ready) return 'real';
    final value = _cacheBox.get(_nfcModeKey);
    return value == 'test' ? 'test' : 'real';
  }

  bool get isNfcTestMode => nfcMode == 'test';

  Future<void> setNfcMode(String mode) async {
    _ensureReady();
    if (mode != 'test' && mode != 'real') {
      throw ArgumentError.value(mode, 'mode', 'Mod NFC tidak sah.');
    }
    await _cacheBox.put(_nfcModeKey, mode);
    notifyListeners();
  }

  Future<void> purgeSyncedOlderThan(Duration age) async {
    if (!_ready) return;
    final cutoff = DateTime.now().subtract(age);
    final keys = <dynamic>[];
    for (final key in _eventsBox.keys) {
      final value = _eventsBox.get(key);
      if (value is! Map) continue;
      try {
        final event = OfflineEvent.fromJson(Map<String, dynamic>.from(value));
        if (event.isSynced && event.occurredAt.isBefore(cutoff)) keys.add(key);
      } catch (_) {}
    }
    if (keys.isNotEmpty) await _eventsBox.deleteAll(keys);
  }

  OfflineEvent? _event(String id) {
    if (!_ready) return null;
    final value = _eventsBox.get(id);
    if (value is! Map) return null;
    try {
      return OfflineEvent.fromJson(Map<String, dynamic>.from(value));
    } catch (_) {
      return null;
    }
  }

  void _ensureReady() {
    if (!_ready) throw StateError('OfflineStore belum diinisialisasi.');
  }

  Map<String, dynamic> _userToJson(AppUser user) => {
    'id': user.id,
    'nama': user.nama,
    'noKadPengenalan': user.noKadPengenalan,
    'jawatan': user.jawatan,
    'jabatan': user.jabatan,
    'profilePicture': user.profilePicture,
    'departmentId': user.departmentId,
    'sessionIntervalMinutes': user.sessionIntervalMinutes,
    'sessionStartMinutes': user.sessionStartMinutes,
    'noPk': user.noPk,
    'guardStatus': user.guardStatus,
    'active': user.active,
  };
}
