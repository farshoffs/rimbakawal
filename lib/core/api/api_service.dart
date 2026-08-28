import 'dart:convert';

import 'package:http/http.dart' as http;

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
    final department = json['department'] as Map<String, dynamic>;
    final rows = json['checkpoints'] as List<dynamic>? ?? const [];
    final next = json['nextCheckpoint'] as Map<String, dynamic>?;
    return PatrolConfig(
      departmentId: (department['id'] as num).toInt(),
      departmentName: department['name'] as String,
      sessionIntervalMinutes: (department['sessionIntervalMinutes'] as num)
          .toInt(),
      routeOrderEnforced: department['routeOrderEnforced'] as bool? ?? false,
      checkpoints: rows
          .map(
            (item) => PatrolCheckpoint.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      sessionIndex: (json['sessionIndex'] as num?)?.toInt() ?? 0,
      nextCheckpoint: next == null
          ? null
          : PatrolCheckpoint.fromJson({...next, 'completed': false}),
    );
  }
}

class HistoryDay {
  const HistoryDay({
    required this.date,
    required this.department,
    required this.sessionIntervalMinutes,
    required this.sessions,
  });
  final String date;
  final String department;
  final int sessionIntervalMinutes;
  final List<HistorySession> sessions;
  factory HistoryDay.fromJson(Map<String, dynamic> json) {
    final sessions = json['sessions'] as List<dynamic>? ?? const [];
    return HistoryDay(
      date: json['date'] as String,
      department: json['department'] as String? ?? '-',
      sessionIntervalMinutes:
          (json['sessionIntervalMinutes'] as num?)?.toInt() ?? 120,
      sessions: sessions
          .map((item) => HistorySession.fromJson(item as Map<String, dynamic>))
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
          .map((item) => (item as Map<String, dynamic>)['name'] as String)
          .toList(),
      scans: scans
          .map((item) => NfcLog.fromJson(item as Map<String, dynamic>))
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
    required this.active,
    required this.checkpointCount,
  });
  final int id;
  final String name;
  final int sessionIntervalMinutes;
  final bool active;
  final int checkpointCount;
  factory DepartmentRecord.fromJson(Map<String, dynamic> json) =>
      DepartmentRecord(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        sessionIntervalMinutes: (json['sessionIntervalMinutes'] as num).toInt(),
        active: json['active'] as bool? ?? true,
        checkpointCount: (json['checkpointCount'] as num?)?.toInt() ?? 0,
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
  });
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> patrols;
  final List<Map<String, dynamic>> incidents;
  final List<Map<String, dynamic>> sosEvents;
  final DateTime generatedAt;
  factory CommandCenterData.fromJson(Map<String, dynamic> json) =>
      CommandCenterData(
        summary: Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
        patrols: (json['patrols'] as List<dynamic>? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        incidents: (json['incidents'] as List<dynamic>? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        sosEvents: (json['sosEvents'] as List<dynamic>? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        generatedAt: DateTime.parse(json['generatedAt'] as String),
      );
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();
  String? _sessionToken;

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
    _sessionToken = data['sessionToken'] as String?;
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AppUser?> getSession() async {
    final response = await http.get(
      _uri('/api/auth/session'),
      headers: _headers(),
    );
    if (response.statusCode == 401) return null;
    return AppUser.fromJson(_decode(response)['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await http.post(_uri('/api/auth/logout'), headers: _headers());
    } finally {
      _sessionToken = null;
    }
  }

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
    return NfcLog.fromJson(data['scan'] as Map<String, dynamic>);
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
    return (data['patrolSession']['id'] as num).toInt();
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

  Future<HistoryDay> getHistory(DateTime date) async => HistoryDay.fromJson(
    _decode(
      await http.get(
        _uri('/api/scans', {'date': _dateKey(date)}),
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
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<List<AppUser>> getAdminUsers() async {
    final data = _decode(
      await http.get(_uri('/api/admin/users'), headers: _headers()),
    );
    return (data['users'] as List<dynamic>? ?? const [])
        .map((item) => AppUser.fromJson(item as Map<String, dynamic>))
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
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
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

  Future<void> createSos({String? note}) async => _decode(
    await http.post(
      _uri('/api/sos'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'note': note}),
    ),
  ) as dynamic;

  Future<List<DepartmentRecord>> getAdminDepartments() async {
    final data = _decode(
      await http.get(_uri('/api/admin/departments'), headers: _headers()),
    );
    return (data['departments'] as List<dynamic>? ?? const [])
        .map((item) => DepartmentRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<DepartmentRecord> createDepartment({
    required String name,
    required int sessionIntervalMinutes,
  }) async {
    final data = _decode(
      await http.post(
        _uri('/api/admin/departments'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'name': name,
          'sessionIntervalMinutes': sessionIntervalMinutes,
        }),
      ),
    );
    return DepartmentRecord.fromJson(
      data['department'] as Map<String, dynamic>,
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
          'active': department.active,
        }),
      ),
    );
    return DepartmentRecord.fromJson(
      data['department'] as Map<String, dynamic>,
    );
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
        .map((item) => CheckpointRecord.fromJson(item as Map<String, dynamic>))
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
      data['checkpoint'] as Map<String, dynamic>,
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
      data['checkpoint'] as Map<String, dynamic>,
    );
  }

  Future<AppUser> updateUserDepartment(int userId, int departmentId) async {
    final data = _decode(
      await http.put(
        _uri('/api/admin/users/$userId/department'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({'departmentId': departmentId}),
      ),
    );
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  String _dateKey(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty)
      data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        data['error'] as String? ?? 'Permintaan gagal.',
        statusCode: response.statusCode,
      );
    }
    return data;
  }
}
