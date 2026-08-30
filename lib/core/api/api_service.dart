import 'dart:convert';

import 'package:http/http.dart' as http;

import '../offline/local_session_vault.dart';
import '../offline/offline_models.dart';
import '../offline/offline_store.dart';
import 'app_user.dart';

const _defaultApiBase = 'https://rimbakawal.fscapitalmanagement.workers.dev';
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: _defaultApiBase,
);

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class NfcLog {
  const NfcLog({
    required this.id,
    required this.nfcUid,
    required this.scannedAt,
    this.checkpointId,
    this.checkpointName,
    this.sessionIndex,
    this.userId,
    this.userName,
    this.profilePicture,
  });
  final int? id;
  final String nfcUid;
  final DateTime scannedAt;
  final int? checkpointId;
  final String? checkpointName;
  final int? sessionIndex;
  final int? userId;
  final String? userName;
  final String? profilePicture;

  factory NfcLog.fromJson(Map<String, dynamic> json) => NfcLog(
    id: (json['id'] as num?)?.toInt(),
    nfcUid: (json['nfc_uid'] ?? json['nfcUid']) as String,
    scannedAt: DateTime.parse(
      (json['scanned_at'] ?? json['scannedAt']) as String,
    ),
    checkpointId: (json['checkpoint_id'] ?? json['checkpointId']) is num
        ? ((json['checkpoint_id'] ?? json['checkpointId']) as num).toInt()
        : null,
    checkpointName:
        (json['checkpoint_name'] ?? json['checkpointName']) as String?,
    sessionIndex: (json['session_index'] ?? json['sessionIndex']) is num
        ? ((json['session_index'] ?? json['sessionIndex']) as num).toInt()
        : null,
    userId: (json['user_id'] ?? json['userId']) is num
        ? ((json['user_id'] ?? json['userId']) as num).toInt()
        : null,
    userName: (json['user_name'] ?? json['userName']) as String?,
    profilePicture:
        (json['profile_picture'] ?? json['profilePicture']) as String?,
  );
}

class PatrolCheckpoint {
  const PatrolCheckpoint({
    required this.id,
    required this.name,
    required this.position,
    required this.completed,
    this.instruction,
  });
  final int id;
  final String name;
  final int position;
  final bool completed;
  final String? instruction;

  factory PatrolCheckpoint.fromJson(Map<String, dynamic> json) =>
      PatrolCheckpoint(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        position: (json['position'] as num).toInt(),
        completed: json['completed'] as bool? ?? false,
        instruction: json['instruction'] as String?,
      );
}

class PatrolConfig {
  const PatrolConfig({
    required this.departmentId,
    required this.departmentName,
    required this.sessionIntervalMinutes,
    required this.routeOrderEnforced,
    required this.checkpoints,
    required this.sessionIndex,
    this.nextCheckpoint,
  });
  final int departmentId;
  final String departmentName;
  final int sessionIntervalMinutes;
  final bool routeOrderEnforced;
  final List<PatrolCheckpoint> checkpoints;
  final int sessionIndex;
  final PatrolCheckpoint? nextCheckpoint;

  List<String> get checkpointNames =>
      checkpoints.map((item) => item.name).toList();
  int get completedCount => checkpoints.where((item) => item.completed).length;

  factory PatrolConfig.fromJson(Map<String, dynamic> json) {
    final department = Map<String, dynamic>.from(json['department'] as Map);
    final rows = json['checkpoints'] as List<dynamic>? ?? const [];
    final next = json['nextCheckpoint'] is Map
        ? Map<String, dynamic>.from(json['nextCheckpoint'] as Map)
        : null;
    return PatrolConfig(
      departmentId: (department['id'] as num).toInt(),
      departmentName: department['name'] as String,
      sessionIntervalMinutes:
          (department['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,
      routeOrderEnforced: department['routeOrderEnforced'] as bool? ?? false,
      checkpoints: rows
          .map(
            (item) => PatrolCheckpoint.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      sessionIndex: (json['sessionIndex'] as num?)?.toInt() ?? 0,
      nextCheckpoint: next == null
          ? null
          : PatrolCheckpoint.fromJson({...next, 'completed': false}),
    );
  }
}

class HistoryTrailPoint {
  const HistoryTrailPoint({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracy,
  });
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;

  factory HistoryTrailPoint.fromJson(Map<String, dynamic> json) =>
      HistoryTrailPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(json['recordedAt'] as String),
      );
}

class HistoryPatrolRun {
  const HistoryPatrolRun({
    required this.userId,
    required this.userName,
    required this.clientSessionId,
    required this.sessionIndex,
    required this.startedAt,
    required this.trailPointCount,
    required this.trail,
    required this.status,
    required this.expectedCount,
    required this.scannedCount,
    required this.missingCheckpointNames,
    required this.scans,
    this.profilePicture,
    this.endedAt,
    this.durationSeconds,
  });
  final int userId;
  final String userName;
  final String? profilePicture;
  final String clientSessionId;
  final int sessionIndex;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final int trailPointCount;
  final List<HistoryTrailPoint> trail;
  final String status;
  final int expectedCount;
  final int scannedCount;
  final List<String> missingCheckpointNames;
  final List<NfcLog> scans;
  bool get isComplete => status == 'complete';
  bool get isInProgress => status == 'in_progress';

  factory HistoryPatrolRun.fromJson(Map<String, dynamic> json) {
    final rows = json['trail'] as List<dynamic>? ?? const [];
    final missing = json['missingCheckpoints'] as List<dynamic>? ?? const [];
    final scans = json['scans'] as List<dynamic>? ?? const [];
    return HistoryPatrolRun(
      userId: (json['userId'] as num).toInt(),
      userName: json['userName'] as String? ?? 'Pengawal',
      profilePicture: json['profilePicture'] as String?,
      clientSessionId: json['clientSessionId'] as String,
      sessionIndex: (json['sessionIndex'] as num?)?.toInt() ?? 0,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] == null
          ? null
          : DateTime.parse(json['endedAt'] as String),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      trailPointCount:
          (json['trailPointCount'] as num?)?.toInt() ?? rows.length,
      trail: rows
          .map(
            (item) => HistoryTrailPoint.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      status: json['status'] as String? ?? 'incomplete',
      expectedCount: (json['expectedCount'] as num?)?.toInt() ?? 0,
      scannedCount: (json['scannedCount'] as num?)?.toInt() ?? 0,
      missingCheckpointNames: missing
          .map(
            (item) =>
                (Map<String, dynamic>.from(item as Map))['name'] as String,
          )
          .toList(),
      scans: scans
          .map(
            (item) => NfcLog.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }
}

class HistoryDay {
  const HistoryDay({
    required this.date,
    required this.departmentId,
    required this.department,
    required this.sessionIntervalMinutes,
    required this.patrolRuns,
    required this.sessions,
  });
  final String date;
  final int departmentId;
  final String department;
  final int sessionIntervalMinutes;
  final List<HistoryPatrolRun> patrolRuns;
  final List<HistorySession> sessions;

  factory HistoryDay.fromJson(Map<String, dynamic> json) {
    final patrolRuns = json['patrolRuns'] as List<dynamic>? ?? const [];
    final sessions = json['sessions'] as List<dynamic>? ?? const [];
    return HistoryDay(
      date: json['date'] as String,
      departmentId: (json['departmentId'] as num?)?.toInt() ?? 0,
      department: json['department'] as String? ?? '-',
      sessionIntervalMinutes:
          (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,
      patrolRuns: patrolRuns
          .map(
            (item) => HistoryPatrolRun.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      sessions: sessions
          .map(
            (item) =>
                HistorySession.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }
}

class HistorySession {
  const HistorySession({
    required this.index,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.expectedCount,
    required this.scannedCount,
    required this.missingCheckpointNames,
    required this.scans,
    required this.userId,
    required this.userName,
    this.profilePicture,
  });
  final int index;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final int expectedCount;
  final int scannedCount;
  final List<String> missingCheckpointNames;
  final List<NfcLog> scans;
  final int userId;
  final String userName;
  final String? profilePicture;
  bool get isMissed => status == 'missed';
  bool get isComplete => status == 'complete';
  bool get isInProgress => status == 'in_progress';

  factory HistorySession.fromJson(Map<String, dynamic> json) {
    final missing = json['missingCheckpoints'] as List<dynamic>? ?? const [];
    final scans = json['scans'] as List<dynamic>? ?? const [];
    return HistorySession(
      index: (json['index'] as num).toInt(),
      startAt: DateTime.parse(json['startAt'] as String),
      endAt: DateTime.parse(json['endAt'] as String),
      status: json['status'] as String,
      expectedCount: (json['expectedCount'] as num?)?.toInt() ?? 0,
      scannedCount: (json['scannedCount'] as num?)?.toInt() ?? 0,
      missingCheckpointNames: missing
          .map(
            (item) =>
                (Map<String, dynamic>.from(item as Map))['name'] as String,
          )
          .toList(),
      scans: scans
          .map(
            (item) => NfcLog.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: json['userName'] as String? ?? 'Pengguna',
      profilePicture: json['profilePicture'] as String?,
    );
  }
}

class DepartmentRecord {
  const DepartmentRecord({
    required this.id,
    required this.name,
    required this.sessionIntervalMinutes,
    this.sessionStartMinutes = 420,
    required this.active,
    required this.checkpointCount,
    this.attendanceLatitude,
    this.attendanceLongitude,
    this.attendanceRadiusMeters = 200,
  });
  final int id;
  final String name;
  final int sessionIntervalMinutes;
  final int sessionStartMinutes;
  final bool active;
  final int checkpointCount;
  final double? attendanceLatitude;
  final double? attendanceLongitude;
  final int attendanceRadiusMeters;

  factory DepartmentRecord.fromJson(Map<String, dynamic> json) =>
      DepartmentRecord(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        sessionIntervalMinutes:
            (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,
        sessionStartMinutes:
            (json['sessionStartMinutes'] as num?)?.toInt() ?? 420,
        active: json['active'] as bool? ?? true,
        checkpointCount: (json['checkpointCount'] as num?)?.toInt() ?? 0,
        attendanceLatitude: (json['attendanceLatitude'] as num?)?.toDouble(),
        attendanceLongitude: (json['attendanceLongitude'] as num?)?.toDouble(),
        attendanceRadiusMeters:
            (json['attendanceRadiusMeters'] as num?)?.toInt() ?? 200,
      );
}

class AttendanceRecord {
  const AttendanceRecord(this.data);
  final Map<String, dynamic> data;
  int get id => (data['id'] as num).toInt();
  String get eventType => data['eventType'] as String? ?? 'in';
  String get status => data['status'] as String? ?? 'rejected';
  String? get rejectionReason => data['rejectionReason'] as String?;
  DateTime get recordedAt => DateTime.parse(data['recordedAt'] as String);
  double get distanceMeters => (data['distanceMeters'] as num?)?.toDouble() ?? 0;
  double? get faceSimilarity => (data['faceSimilarity'] as num?)?.toDouble();
  bool get faceMatched => data['faceMatched'] as bool? ?? false;
  String? get nama => data['nama'] as String?;
  String? get jabatan => data['jabatan'] as String?;
}

class AttendanceStatus {
  const AttendanceStatus({
    required this.department,
    required this.hasProfilePicture,
    required this.profilePicture,
    required this.faceThreshold,
    required this.nextEventType,
    required this.records,
  });
  final Map<String, dynamic> department;
  final bool hasProfilePicture;
  final String? profilePicture;
  final double faceThreshold;
  final String nextEventType;
  final List<AttendanceRecord> records;

  factory AttendanceStatus.fromJson(Map<String, dynamic> json) => AttendanceStatus(
        department: Map<String, dynamic>.from(json['department'] as Map),
        hasProfilePicture: json['hasProfilePicture'] as bool? ?? false,
        profilePicture: json['profilePicture'] as String?,
        faceThreshold: (json['faceThreshold'] as num?)?.toDouble() ?? .6,
        nextEventType: json['nextEventType'] as String? ?? 'in',
        records: (json['records'] as List<dynamic>? ?? const [])
            .map((item) => AttendanceRecord(Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

class CheckpointRecord {
  const CheckpointRecord({
    required this.id,
    required this.departmentId,
    required this.name,
    required this.nfcUid,
    required this.position,
    required this.active,
  });
  final int id;
  final int departmentId;
  final String name;
  final String nfcUid;
  final int position;
  final bool active;

  factory CheckpointRecord.fromJson(Map<String, dynamic> json) =>
      CheckpointRecord(
        id: (json['id'] as num).toInt(),
        departmentId: (json['departmentId'] as num).toInt(),
        name: json['name'] as String,
        nfcUid: json['nfcUid'] as String,
        position: (json['position'] as num).toInt(),
        active: json['active'] as bool? ?? true,
      );
}

class CommandCenterData {
  const CommandCenterData({
    required this.summary,
    required this.patrols,
    required this.incidents,
    required this.sosEvents,
    required this.generatedAt,
    required this.attendance,
  });
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> patrols;
  final List<Map<String, dynamic>> incidents;
  final List<Map<String, dynamic>> sosEvents;
  final DateTime generatedAt;
  final List<Map<String, dynamic>> attendance;

  factory CommandCenterData.fromJson(Map<String, dynamic> json) =>
      CommandCenterData(
        summary: Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
        patrols: (json['patrols'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        incidents: (json['incidents'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        sosEvents: (json['sosEvents'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        generatedAt: DateTime.parse(json['generatedAt'] as String),
        attendance: (json['attendance'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
      );
}

class LiveMapData {
  const LiveMapData({required this.generatedAt, required this.patrols});
  final DateTime generatedAt;
  final List<Map<String, dynamic>> patrols;

  factory LiveMapData.fromJson(Map<String, dynamic> json) => LiveMapData(
    generatedAt: DateTime.parse(json['generatedAt'] as String),
    patrols: (json['patrols'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(),
  );
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final LocalSessionVault _vault = LocalSessionVault.instance;
  final OfflineStore _offline = OfflineStore.instance;
  String? _sessionToken;

  bool get hasSessionToken =>
      _sessionToken != null && _sessionToken!.isNotEmpty;

  Future<void> init() async {
    _sessionToken = await _vault.readToken();
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);

  Map<String, String> _headers({bool jsonBody = false}) => {
    if (jsonBody) 'Content-Type': 'application/json',
    if (_sessionToken != null) 'Authorization': 'Bearer $_sessionToken',
  };

  Future<AppUser> login(String identityCard) async {
    final response = await http.post(
      _uri('/api/auth/login'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'identityCard': identityCard}),
    );
    final data = _decode(response);
    final token = data['sessionToken'] as String?;
    if (token == null || token.isEmpty) {
      throw const ApiException('Token sesi tidak diterima.');
    }
    _sessionToken = token;
    await _vault.writeToken(token);
    final user = AppUser.fromJson(
      Map<String, dynamic>.from(data['user'] as Map),
    );
    await _offline.cacheUser(user);
    try {
      await getOfflineBootstrap();
    } catch (_) {}
    return user;
  }

  Future<AppUser?> getSession() async {
    if (_sessionToken == null || _sessionToken!.isEmpty) {
      await _offline.clearCachedUser();
      return null;
    }

    final cached = _offline.cachedUser();
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

  Future<void> logout() async {
    try {
      if (_sessionToken != null) {
        await http.post(_uri('/api/auth/logout'), headers: _headers());
      }
    } catch (_) {
      // Local logout must still succeed when offline.
    } finally {
      _sessionToken = null;
      await _vault.clearToken();
      await _offline.clearCachedUser();
    }
  }

  Future<void> registerPushDevice({
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

  Future<OfflineBootstrap> getOfflineBootstrap() async {
    final data = _decode(
      await http.get(_uri('/api/offline/bootstrap'), headers: _headers()),
    );
    final bootstrap = OfflineBootstrap.fromJson(data);
    await _offline.cacheBootstrap(bootstrap);
    await _offline.cacheUser(bootstrap.user);
    return bootstrap;
  }

  Future<List<Map<String, dynamic>>> syncOfflineEvents(
    List<OfflineEvent> events,
  ) async {
    if (events.isEmpty) return const [];
    final data = _decode(
      await http.post(
        _uri('/api/offline/sync'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'events': events.map((event) => event.toSyncJson()).toList(),
        }),
      ),
    );
    return (data['results'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> startLivePatrol(
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

  Future<void> updateLivePatrolLocation(
    String clientSessionId, {
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    _decode(
      await http.post(
        _uri('/api/live/location'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'clientSessionId': clientSessionId,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
        }),
      ),
    );
  }

  Future<void> endLivePatrol(String clientSessionId) async {
    _decode(
      await http.post(
        _uri('/api/live/end'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'clientSessionId': clientSessionId}),
      ),
    );
  }

  Future<LiveMapData> getLiveMap() async => LiveMapData.fromJson(
    _decode(await http.get(_uri('/api/monitor/live-map'), headers: _headers())),
  );

  Future<PatrolConfig> getPatrolConfig() async => PatrolConfig.fromJson(
    _decode(await http.get(_uri('/api/patrol/config'), headers: _headers())),
  );

  Future<NfcLog> storeNfcScan(String uid) async {
    final data = _decode(
      await http.post(
        _uri('/api/scans'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'nfcUid': uid}),
      ),
    );
    return NfcLog.fromJson(Map<String, dynamic>.from(data['scan'] as Map));
  }

  Future<void> createIncident({
    required int? checkpointId,
    required String category,
    required String severity,
    required String note,
    List<String> images = const [],
  }) async {
    _decode(
      await http.post(
        _uri('/api/incidents'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'checkpointId': checkpointId,
          'category': category,
          'severity': severity,
          'note': note,
          'images': images,
        }),
      ),
    );
  }

  Future<int> startPatrolSession() async {
    final data = _decode(
      await http.post(
        _uri('/api/patrol/start'),
        headers: _headers(jsonBody: true),
        body: '{}',
      ),
    );
    return (Map<String, dynamic>.from(data['patrolSession'] as Map)['id']
            as num)
        .toInt();
  }

  Future<void> updatePatrolLocation(
    int patrolSessionId, {
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    _decode(
      await http.post(
        _uri('/api/patrol/location'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'patrolSessionId': patrolSessionId,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
        }),
      ),
    );
  }

  Future<void> endPatrolSession(int patrolSessionId) async {
    _decode(
      await http.post(
        _uri('/api/patrol/end'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'patrolSessionId': patrolSessionId}),
      ),
    );
  }

  Future<List<String>> getIncidentImages(int incidentId) async {
    final data = _decode(
      await http.get(
        _uri('/api/admin/incidents/$incidentId/images'),
        headers: _headers(),
      ),
    );
    return (data['images'] as List<dynamic>? ?? const [])
        .map((item) => item as String)
        .toList();
  }

  Future<CommandCenterData> getCommandCenter() async =>
      CommandCenterData.fromJson(
        _decode(
          await http.get(
            _uri('/api/admin/command-center'),
            headers: _headers(),
          ),
        ),
      );

  Future<void> updateIncidentStatus(int id, String status) async {
    _decode(
      await http.put(
        _uri('/api/admin/incidents/$id/status'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'status': status}),
      ),
    );
  }

  Future<HistoryDay> getHistory(DateTime date, {int? departmentId}) async =>
      HistoryDay.fromJson(
        _decode(
          await http.get(
            _uri('/api/scans', {
              'date': _dateKey(date),
              if (departmentId != null) 'departmentId': departmentId.toString(),
            }),
            headers: _headers(),
          ),
        ),
      );

  Future<AppUser> updateProfilePicture(String dataUrl) async {
    final data = _decode(
      await http.post(
        _uri('/api/profile/picture'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'profilePicture': dataUrl}),
      ),
    );
    final user = AppUser.fromJson(
      Map<String, dynamic>.from(data['user'] as Map),
    );
    await _offline.cacheUser(user);
    return user;
  }

  Future<List<AppUser>> getAdminUsers() async {
    final data = _decode(
      await http.get(_uri('/api/admin/users'), headers: _headers()),
    );
    return (data['users'] as List<dynamic>? ?? const [])
        .map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<AppUser> createAdminUser({
    required String nama,
    required String noKadPengenalan,
    required String jawatan,
    required int departmentId,
  }) async {
    final data = _decode(
      await http.post(
        _uri('/api/admin/users'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'nama': nama,
          'noKadPengenalan': noKadPengenalan,
          'jawatan': jawatan,
          'departmentId': departmentId,
        }),
      ),
    );
    return AppUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<Map<String, dynamic>> getAdminReport(
    DateTime from,
    DateTime to, {
    int? departmentId,
  }) async => _decode(
    await http.get(
      _uri('/api/admin/reports', {
        'from': _dateKey(from),
        'to': _dateKey(to),
        if (departmentId != null) 'departmentId': departmentId.toString(),
      }),
      headers: _headers(),
    ),
  );

  Future<void> createSos({String? note}) async {
    _decode(
      await http.post(
        _uri('/api/sos'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'note': note}),
      ),
    );
  }

  Future<List<DepartmentRecord>> getAdminDepartments() async {
    final data = _decode(
      await http.get(_uri('/api/admin/departments'), headers: _headers()),
    );
    return (data['departments'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              DepartmentRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<DepartmentRecord> createDepartment({
    required String name,
    required int sessionIntervalMinutes,
    int sessionStartMinutes = 420,
    double? attendanceLatitude,
    double? attendanceLongitude,
    int attendanceRadiusMeters = 200,
  }) async {
    final data = _decode(
      await http.post(
        _uri('/api/admin/departments'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'name': name,
          'sessionIntervalMinutes': sessionIntervalMinutes,
          'sessionStartMinutes': sessionStartMinutes,
          'attendanceLatitude': attendanceLatitude,
          'attendanceLongitude': attendanceLongitude,
          'attendanceRadiusMeters': attendanceRadiusMeters,
        }),
      ),
    );
    return DepartmentRecord.fromJson(
      Map<String, dynamic>.from(data['department'] as Map),
    );
  }

  Future<DepartmentRecord> updateDepartment(DepartmentRecord department) async {
    final data = _decode(
      await http.put(
        _uri('/api/admin/departments/${department.id}'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'name': department.name,
          'sessionIntervalMinutes': department.sessionIntervalMinutes,
          'sessionStartMinutes': department.sessionStartMinutes,
          'active': department.active,
          'attendanceLatitude': department.attendanceLatitude,
          'attendanceLongitude': department.attendanceLongitude,
          'attendanceRadiusMeters': department.attendanceRadiusMeters,
        }),
      ),
    );
    return DepartmentRecord.fromJson(
      Map<String, dynamic>.from(data['department'] as Map),
    );
  }

  Future<AttendanceStatus> getAttendanceStatus() async =>
      AttendanceStatus.fromJson(
        _decode(
          await http.get(_uri('/api/attendance/status'), headers: _headers()),
        ),
      );

  Future<AttendanceRecord> punchAttendance({
    required double latitude,
    required double longitude,
    required double accuracy,
    required bool faceDetected,
    required bool faceMatched,
    required double faceSimilarity,
    required String selfieImage,
    required String devicePlatform,
  }) async {
    final data = _decode(
      await http.post(
        _uri('/api/attendance/punch'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'faceDetected': faceDetected,
          'faceMatched': faceMatched,
          'faceSimilarity': faceSimilarity,
          'selfieImage': selfieImage,
          'devicePlatform': devicePlatform,
        }),
      ),
    );
    return AttendanceRecord(Map<String, dynamic>.from(data['record'] as Map));
  }

  Future<List<AttendanceRecord>> getAdminAttendance(
    DateTime date, {
    int? departmentId,
  }) async {
    final data = _decode(
      await http.get(
        _uri('/api/admin/attendance', {
          'date': _dateKey(date),
          if (departmentId != null) 'departmentId': '$departmentId',
        }),
        headers: _headers(),
      ),
    );
    return (data['records'] as List<dynamic>? ?? const [])
        .map((item) => AttendanceRecord(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<String> getAttendanceEvidence(int id) async {
    final data = _decode(
      await http.get(
        _uri('/api/admin/attendance/$id/evidence'),
        headers: _headers(),
      ),
    );
    return data['selfieImage'] as String;
  }

  Future<List<CheckpointRecord>> getAdminCheckpoints(int departmentId) async {
    final data = _decode(
      await http.get(
        _uri('/api/admin/checkpoints', {
          'departmentId': departmentId.toString(),
        }),
        headers: _headers(),
      ),
    );
    return (data['checkpoints'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              CheckpointRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<CheckpointRecord> createCheckpoint({
    required int departmentId,
    required String name,
    required String nfcUid,
    required int position,
  }) async {
    final data = _decode(
      await http.post(
        _uri('/api/admin/checkpoints'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'departmentId': departmentId,
          'name': name,
          'nfcUid': nfcUid,
          'position': position,
        }),
      ),
    );
    return CheckpointRecord.fromJson(
      Map<String, dynamic>.from(data['checkpoint'] as Map),
    );
  }

  Future<CheckpointRecord> updateCheckpoint(CheckpointRecord checkpoint) async {
    final data = _decode(
      await http.put(
        _uri('/api/admin/checkpoints/${checkpoint.id}'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'departmentId': checkpoint.departmentId,
          'name': checkpoint.name,
          'nfcUid': checkpoint.nfcUid,
          'position': checkpoint.position,
          'active': checkpoint.active,
        }),
      ),
    );
    return CheckpointRecord.fromJson(
      Map<String, dynamic>.from(data['checkpoint'] as Map),
    );
  }

  Future<AppUser> updateAdminUser({
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
    };
    if (profilePicture != null) body['profilePicture'] = profilePicture;
    if (clearProfilePicture) body['clearProfilePicture'] = true;
    final data = _decode(
      await http.put(
        _uri('/api/admin/users/$userId'),
        headers: _headers(jsonBody: true),
        body: jsonEncode(body),
      ),
    );
    return AppUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<AppUser> updateUserDepartment(int userId, int departmentId) async {
    final data = _decode(
      await http.put(
        _uri('/api/admin/users/$userId/department'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'departmentId': departmentId}),
      ),
    );
    return AppUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  String _dateKey(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  bool _tokenBelongsToCurrentSession(AppUser user) {
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

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        data = {'error': 'Respons pelayan tidak sah.'};
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        data['error'] as String? ?? 'Permintaan gagal.',
        statusCode: response.statusCode,
      );
    }
    return data;
  }
}
