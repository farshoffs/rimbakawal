from pathlib import Path
import re


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding='utf-8')


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly 1 match, got {count}')
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly 1 regex match, got {count}')
    return updated


# Persist the logical active patrol independently of screen navigation.
p = 'lib/core/offline/offline_store.dart'
t = read(p)
t = once(
    t,
    "  static const _nfcModeKey = 'nfc_operation_mode';\n",
    "  static const _nfcModeKey = 'nfc_operation_mode';\n  static const _activePatrolKeyPrefix = 'active_patrol_';\n",
    'active patrol cache key',
)
t = once(
    t,
    "  Future<OfflineEvent> queueEvent({\n",
    r'''  Map<String, dynamic>? activePatrol(int userId) {
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

  Future<void> clearActivePatrol(
    int userId, {
    String? clientSessionId,
  }) async {
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
''',
    'active patrol store methods',
)
t = once(
    t,
    "    'sessionIntervalMinutes': user.sessionIntervalMinutes,\n    'active': user.active,",
    "    'sessionIntervalMinutes': user.sessionIntervalMinutes,\n    'sessionStartMinutes': user.sessionStartMinutes,\n    'active': user.active,",
    'cache user session start',
)
write(p, t)


# Let the caller know whether the server resumed an already-active patrol.
p = 'lib/core/api/api_service.dart'
t = read(p)
t = once(
    t,
    r'''  Future<void> startLivePatrol(
    String clientSessionId,
    DateTime startedAt,
  ) async {
    _decode(
      await http.post(
        _uri('/api/live/start'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'clientSessionId': clientSessionId,
          'startedAt': startedAt.toUtc().toIso8601String(),
        }),
      ),
    );
  }
''',
    r'''  Future<Map<String, dynamic>> startLivePatrol(
    String clientSessionId,
    DateTime startedAt,
  ) async {
    return _decode(
      await http.post(
        _uri('/api/live/start'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'clientSessionId': clientSessionId,
          'startedAt': startedAt.toUtc().toIso8601String(),
        }),
      ),
    );
  }
''',
    'startLivePatrol return data',
)
write(p, t)


# Patrol screen: resume same slot, do not end on navigation, and roll over at the
# next configured session boundary.
p = 'lib/features/patrol/patrol_screen.dart'
t = read(p)
t = once(
    t,
    r'''  late final String _clientSessionId;
  late final DateTime _startedAt;
  StreamSubscription<Position>? _positionSub;
  Timer? _locationHeartbeat;
''',
    r'''  late String _clientSessionId;
  late DateTime _startedAt;
  StreamSubscription<Position>? _positionSub;
  Timer? _locationHeartbeat;
  Timer? _sessionBoundaryTimer;
''',
    'mutable patrol session fields',
)
old_init = r'''  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _clientSessionId = _store.newId('patrol-session');
    unawaited(WakelockPlus.enable());
    _store.addListener(_onLocalChanged);
    _sync.addListener(_onLocalChanged);
    unawaited(_startOfflinePatrol());
  }

  @override
  void dispose() {
    _store.removeListener(_onLocalChanged);
    _sync.removeListener(_onLocalChanged);
    _positionSub?.cancel();
    _locationHeartbeat?.cancel();
    unawaited(WakelockPlus.disable());
    if (_torchOn && !kIsWeb) unawaited(TorchLight.disableTorch());
    if (!_ending) unawaited(widget.api.endLivePatrol(_clientSessionId));
    super.dispose();
  }

  void _onLocalChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startOfflinePatrol() async {
    await _store.queueEvent(
      userId: widget.user.id,
      type: 'patrol_start',
      occurredAt: _startedAt,
      payload: {'clientSessionId': _clientSessionId},
    );
    unawaited(_sync.syncNow());
    await _loadBootstrap();
    unawaited(_startLiveTracking());
  }
'''
new_init = r'''  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final currentWindow = _sessionWindow(
      now,
      widget.user.sessionIntervalMinutes,
      widget.user.sessionStartMinutes,
    );
    final currentDayKey = _scheduleDayKey(
      now,
      widget.user.sessionStartMinutes,
    );
    final stored = _store.activePatrol(widget.user.id);
    final storedId = stored?['clientSessionId'] as String?;
    final storedStartedAt = DateTime.tryParse(
      stored?['startedAt'] as String? ?? '',
    )?.toLocal();
    final storedSessionIndex = (stored?['sessionIndex'] as num?)?.toInt();
    final storedDayKey = stored?['dayKey'] as String?;
    final canResume = storedId != null &&
        storedStartedAt != null &&
        storedSessionIndex == currentWindow.index &&
        storedDayKey == currentDayKey;

    if (canResume) {
      _clientSessionId = storedId;
      _startedAt = storedStartedAt;
    } else {
      _startedAt = now;
      _clientSessionId = _store.newId('patrol-session');
    }

    unawaited(WakelockPlus.enable());
    _store.addListener(_onLocalChanged);
    _sync.addListener(_onLocalChanged);
    unawaited(
      _startOfflinePatrol(
        previousActive: canResume ? null : stored,
        resumed: canResume,
        currentWindow: currentWindow,
        dayKey: currentDayKey,
      ),
    );
  }

  @override
  void dispose() {
    _store.removeListener(_onLocalChanged);
    _sync.removeListener(_onLocalChanged);
    _positionSub?.cancel();
    _locationHeartbeat?.cancel();
    _sessionBoundaryTimer?.cancel();
    unawaited(WakelockPlus.disable());
    if (_torchOn && !kIsWeb) unawaited(TorchLight.disableTorch());
    // Leaving the screen must not end an active patrol. The same logical
    // patrol is restored when the guard opens Rondaan Aktif again.
    super.dispose();
  }

  void _onLocalChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startOfflinePatrol({
    required Map<String, dynamic>? previousActive,
    required bool resumed,
    required _SessionWindow currentWindow,
    required String dayKey,
  }) async {
    if (previousActive != null) {
      await _autoEndStoredPatrol(previousActive, currentWindow.start);
    }

    var shouldQueueStart = !resumed;
    try {
      final live = await widget.api.startLivePatrol(
        _clientSessionId,
        _startedAt,
      );
      final resolvedId = live['clientSessionId'] as String?;
      final resolvedStartedAt = DateTime.tryParse(
        live['startedAt'] as String? ?? '',
      )?.toLocal();
      if (resolvedId != null && resolvedId.isNotEmpty) {
        if (resolvedId != _clientSessionId || live['resumed'] == true) {
          shouldQueueStart = false;
        }
        _clientSessionId = resolvedId;
      }
      if (resolvedStartedAt != null) _startedAt = resolvedStartedAt;
    } catch (_) {
      // Offline-first: the local session remains authoritative until sync.
    }

    await _store.saveActivePatrol(
      userId: widget.user.id,
      clientSessionId: _clientSessionId,
      startedAt: _startedAt,
      sessionIndex: currentWindow.index,
      dayKey: dayKey,
    );

    if (shouldQueueStart) {
      await _store.queueEvent(
        userId: widget.user.id,
        type: 'patrol_start',
        occurredAt: _startedAt,
        payload: {'clientSessionId': _clientSessionId},
      );
    }
    unawaited(_sync.syncNow());
    await _loadBootstrap();
    _scheduleSessionBoundary();
    unawaited(_startLiveTracking());
  }

  Future<void> _autoEndStoredPatrol(
    Map<String, dynamic> previous,
    DateTime sessionBoundary,
  ) async {
    final previousId = previous['clientSessionId'] as String?;
    if (previousId == null || previousId.isEmpty) return;
    final previousStartedAt = DateTime.tryParse(
      previous['startedAt'] as String? ?? '',
    )?.toLocal();
    final endedAt = previousStartedAt != null &&
            sessionBoundary.isAfter(previousStartedAt)
        ? sessionBoundary
        : DateTime.now();
    await _store.queueEvent(
      userId: widget.user.id,
      type: 'patrol_end',
      occurredAt: endedAt,
      payload: {
        'clientSessionId': previousId,
        'autoEnded': true,
        'reason': 'session_rollover',
      },
    );
    try {
      await widget.api.endLivePatrol(previousId);
    } catch (_) {}
    await _store.clearActivePatrol(
      widget.user.id,
      clientSessionId: previousId,
    );
  }

  void _scheduleSessionBoundary() {
    _sessionBoundaryTimer?.cancel();
    if (_ending) return;
    final now = DateTime.now();
    final window = _sessionWindow(
      now,
      widget.user.sessionIntervalMinutes,
      widget.user.sessionStartMinutes,
    );
    var delay = window.end.difference(now) + const Duration(seconds: 1);
    if (delay <= Duration.zero) delay = const Duration(seconds: 1);
    _sessionBoundaryTimer = Timer(
      delay,
      () => unawaited(_rolloverToCurrentSession()),
    );
  }

  Future<void> _rolloverToCurrentSession() async {
    if (_ending) return;
    final now = DateTime.now();
    final currentWindow = _sessionWindow(
      now,
      widget.user.sessionIntervalMinutes,
      widget.user.sessionStartMinutes,
    );
    final currentDayKey = _scheduleDayKey(
      now,
      widget.user.sessionStartMinutes,
    );
    final oldWindow = _sessionWindow(
      _startedAt,
      widget.user.sessionIntervalMinutes,
      widget.user.sessionStartMinutes,
    );
    final oldDayKey = _scheduleDayKey(
      _startedAt,
      widget.user.sessionStartMinutes,
    );
    if (oldWindow.index == currentWindow.index &&
        oldDayKey == currentDayKey) {
      _scheduleSessionBoundary();
      return;
    }

    final oldId = _clientSessionId;
    await _store.queueEvent(
      userId: widget.user.id,
      type: 'patrol_end',
      occurredAt: currentWindow.start,
      location: await _captureEventLocation(),
      payload: {
        'clientSessionId': oldId,
        'autoEnded': true,
        'reason': 'session_rollover',
      },
    );
    try {
      await widget.api.endLivePatrol(oldId);
    } catch (_) {}
    await _store.clearActivePatrol(
      widget.user.id,
      clientSessionId: oldId,
    );

    _clientSessionId = _store.newId('patrol-session');
    _startedAt = now;
    var shouldQueueStart = true;
    try {
      final live = await widget.api.startLivePatrol(
        _clientSessionId,
        _startedAt,
      );
      final resolvedId = live['clientSessionId'] as String?;
      final resolvedStartedAt = DateTime.tryParse(
        live['startedAt'] as String? ?? '',
      )?.toLocal();
      if (resolvedId != null && resolvedId.isNotEmpty) {
        if (resolvedId != _clientSessionId || live['resumed'] == true) {
          shouldQueueStart = false;
        }
        _clientSessionId = resolvedId;
      }
      if (resolvedStartedAt != null) _startedAt = resolvedStartedAt;
    } catch (_) {}

    await _store.saveActivePatrol(
      userId: widget.user.id,
      clientSessionId: _clientSessionId,
      startedAt: _startedAt,
      sessionIndex: currentWindow.index,
      dayKey: currentDayKey,
    );
    if (shouldQueueStart) {
      await _store.queueEvent(
        userId: widget.user.id,
        type: 'patrol_start',
        occurredAt: _startedAt,
        payload: {'clientSessionId': _clientSessionId},
      );
    }
    unawaited(_sync.syncNow());
    _lastLocationSentAt = null;
    final position = _latestPosition;
    if (position != null) await _handlePosition(position, force: true);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sesi rondaan sebelumnya ditamatkan automatik. Sesi baharu telah bermula.',
          ),
        ),
      );
    }
    _scheduleSessionBoundary();
  }
'''
t = once(t, old_init, new_init, 'patrol lifecycle init/dispose')
t = once(
    t,
    r'''  Future<void> _startLiveTracking() async {
    try {
      await widget.api.startLivePatrol(_clientSessionId, _startedAt);
    } catch (_) {
      // Live map is best effort. Field work remains available offline.
    }

    try {
''',
    r'''  Future<void> _startLiveTracking() async {
    try {
''',
    'remove duplicate live start from tracking',
)
t = once(
    t,
    r'''    try {
      await widget.api.endLivePatrol(_clientSessionId);
    } catch (_) {}
    await _turnOffTorch();
''',
    r'''    try {
      await widget.api.endLivePatrol(_clientSessionId);
    } catch (_) {}
    await _store.clearActivePatrol(
      widget.user.id,
      clientSessionId: _clientSessionId,
    );
    _sessionBoundaryTimer?.cancel();
    await _turnOffTorch();
''',
    'manual finish clears active session',
)
write(p, t)


# Backend guard: if the app lost its local cache, reuse the existing current-slot
# session; if the active session belongs to an older slot, close it at the new
# slot boundary before creating the new one.
p = 'worker/offline.js'
t = read(p)
new_live_start = r'''async function liveStart(request, env) {
  const auth = await requireUser(request, env);
  if (auth.response) return auth.response;
  const body = await readJson(request);
  const requestedSessionId = cleanId(body.clientSessionId);
  const requestedStartedAt = parseOccurredAt(body.startedAt) ?? new Date();
  if (!requestedSessionId) return json({ error: 'ID sesi rondaan tidak sah.' }, 400);

  const now = new Date();
  const interval = Number(auth.user.session_interval_minutes || 120);
  const window = sessionWindow(now, interval, auth.user.session_start_minutes);
  const sessionStart = new Date(window.startMs);
  const sessionEnd = new Date(window.endMs);
  const nowIso = now.toISOString();

  const existing = await env.DB.prepare(
    `SELECT client_session_id, started_at
     FROM live_patrol_presence
     WHERE user_id = ? AND active = 1
     LIMIT 1`,
  ).bind(auth.user.id).first();

  if (existing?.client_session_id && existing?.started_at) {
    const existingStartedAt = new Date(existing.started_at);
    if (!Number.isNaN(existingStartedAt.getTime()) &&
        existingStartedAt >= sessionStart && existingStartedAt < sessionEnd) {
      await env.DB.prepare(
        `UPDATE live_patrol_presence SET updated_at = ? WHERE user_id = ?`,
      ).bind(nowIso, auth.user.id).run();
      return json({
        ok: true,
        resumed: true,
        clientSessionId: existing.client_session_id,
        startedAt: existing.started_at,
        sessionIndex: window.index,
        sessionStartAt: sessionStart.toISOString(),
        sessionEndAt: sessionEnd.toISOString(),
      });
    }

    const rolloverEndedAt = sessionStart.toISOString();
    await env.DB.prepare(
      `UPDATE live_patrol_presence
       SET active = 0, ended_at = ?, updated_at = ?
       WHERE user_id = ? AND active = 1`,
    ).bind(rolloverEndedAt, nowIso, auth.user.id).run();
    await env.DB.prepare(
      `UPDATE patrol_session_history
       SET ended_at = COALESCE(ended_at, ?), updated_at = ?
       WHERE user_id = ? AND client_session_id = ?`,
    ).bind(
      rolloverEndedAt,
      nowIso,
      auth.user.id,
      existing.client_session_id,
    ).run();
  }

  const effectiveStartedAt = requestedStartedAt >= sessionStart &&
          requestedStartedAt < sessionEnd
      ? requestedStartedAt
      : now;
  const startedAtIso = effectiveStartedAt.toISOString();

  await env.DB.prepare(
    `INSERT INTO live_patrol_presence
      (user_id, department_id, client_session_id, started_at, active, updated_at)
     VALUES (?, ?, ?, ?, 1, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       department_id = excluded.department_id,
       client_session_id = excluded.client_session_id,
       started_at = excluded.started_at,
       ended_at = NULL,
       active = 1,
       last_latitude = NULL,
       last_longitude = NULL,
       last_accuracy = NULL,
       last_location_at = NULL,
       updated_at = excluded.updated_at`,
  ).bind(
    auth.user.id,
    auth.user.department_id ?? null,
    requestedSessionId,
    startedAtIso,
    nowIso,
  ).run();

  await env.DB.prepare(
    `INSERT INTO patrol_session_history
      (user_id, department_id, client_session_id, started_at, ended_at, updated_at)
     VALUES (?, ?, ?, ?, NULL, ?)
     ON CONFLICT(user_id, client_session_id) DO UPDATE SET
       department_id = excluded.department_id,
       started_at = CASE
         WHEN excluded.started_at < patrol_session_history.started_at THEN excluded.started_at
         ELSE patrol_session_history.started_at
       END,
       ended_at = NULL,
       updated_at = excluded.updated_at`,
  ).bind(
    auth.user.id,
    auth.user.department_id ?? null,
    requestedSessionId,
    startedAtIso,
    nowIso,
  ).run();

  return json({
    ok: true,
    resumed: false,
    clientSessionId: requestedSessionId,
    startedAt: startedAtIso,
    sessionIndex: window.index,
    sessionStartAt: sessionStart.toISOString(),
    sessionEndAt: sessionEnd.toISOString(),
  });
}
'''
t = regex_once(
    t,
    r"async function liveStart\(request, env\) \{.*?\n\}\n\nasync function liveLocation",
    new_live_start + '\nasync function liveLocation',
    'server liveStart reconciliation',
)
write(p, t)

print('Patrol resume + automatic session rollover patch applied.')
