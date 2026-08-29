import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../api/api_service.dart';
import 'offline_store.dart';

class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService._();

  static final OfflineSyncService instance = OfflineSyncService._();

  final OfflineStore _store = OfflineStore.instance;
  final ApiService _api = ApiService.instance;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _timer;
  bool _started = false;
  bool _syncing = false;
  DateTime? _lastSyncAt;
  String? _lastError;

  bool get isSyncing => _syncing;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastError => _lastError;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      if (_hasNetwork(results)) unawaited(syncNow());
    });
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(syncNow()),
    );
    unawaited(syncNow());
  }

  Future<void> stop() async {
    await _connectivitySub?.cancel();
    _timer?.cancel();
    _connectivitySub = null;
    _timer = null;
    _started = false;
  }

  Future<bool> hasNetwork() async {
    final results = await _connectivity.checkConnectivity();
    return _hasNetwork(results);
  }

  Future<void> syncNow() async {
    if (_syncing || !_api.hasSessionToken || !_store.isReady) return;
    final user = _store.cachedUser();
    if (user == null) return;
    final connectivity = await _connectivity.checkConnectivity();
    if (!_hasNetwork(connectivity)) return;

    final pending = _store.pendingEvents(user.id, limit: 50);
    if (pending.isEmpty) {
      try {
        await _api.getOfflineBootstrap();
        _lastError = null;
      } catch (_) {}
      notifyListeners();
      return;
    }

    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final results = await _api.syncOfflineEvents(pending);
      final byId = {
        for (final row in results) row['id'] as String? ?? '': row,
      };
      for (final event in pending) {
        final result = byId[event.id];
        if (result == null) continue;
        final status = result['status'] as String?;
        if (status == 'synced') {
          await _store.markSynced(event.id);
        } else if (status == 'rejected') {
          await _store.markFailed(
            event.id,
            result['error'] as String? ?? 'Event ditolak oleh pelayan.',
          );
        }
      }
      _lastSyncAt = DateTime.now();
      try {
        await _api.getOfflineBootstrap();
      } catch (_) {}
    } catch (error) {
      _lastError = error.toString();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> retryFailed() async {
    final user = _store.cachedUser();
    if (user == null) return;
    await _store.retryFailed(user.id);
    await syncNow();
  }

  bool _hasNetwork(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.every((item) => item == ConnectivityResult.none);
}
