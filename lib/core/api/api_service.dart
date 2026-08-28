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
  });

  final int? id;
  final String nfcUid;
  final DateTime scannedAt;
  final int? checkpointId;
  final String? checkpointName;
  final int? sessionIndex;

  factory NfcLog.fromJson(Map<String, dynamic> json) {
    return NfcLog(
      id: (json['id'] as num?)?.toInt(),
      nfcUid: (json['nfc_uid'] ?? json['nfcUid']) as String,
      scannedAt: DateTime.parse(
        (json['scanned_at'] ?? json['scannedAt']) as String,
      ),
      checkpointId:
          (json['checkpoint_id'] ?? json['checkpointId']) is num
              ? ((json['checkpoint_id'] ?? json['checkpointId']) as num).toInt()
              : null,
      checkpointName:
          (json['checkpoint_name'] ?? json['checkpointName']) as String?,
      sessionIndex:
          (json['session_index'] ?? json['sessionIndex']) is num
              ? ((json['session_index'] ?? json['sessionIndex']) as num).toInt()
              : null,
    );
  }
}

class PatrolConfig {
  const PatrolConfig({
    required this.departmentId,
    required this.departmentName,
    required this.sessionIntervalMinutes,
    required this.checkpointNames,
  });

  final int departmentId;
  final String departmentName;
  final int sessionIntervalMinutes;
  final List<String> checkpointNames;

  factory PatrolConfig.fromJson(Map<String, dynamic> json) {
    final department = json['department'] as Map<String, dynamic>;
    final checkpoints = json['checkpoints'] as List<dynamic>? ?? const [];
    return PatrolConfig(
      departmentId: (department['id'] as num).toInt(),
      departmentName: department['name'] as String,
      sessionIntervalMinutes:
          (department['sessionIntervalMinutes'] as num).toInt(),
      checkpointNames: checkpoints
          .map((item) => (item as Map<String, dynamic>)['name'] as String)
          .toList(),
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
  });

  final int index;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final int expectedCount;
  final int scannedCount;
  final List<String> missingCheckpointNames;
  final List<NfcLog> scans;

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

  factory DepartmentRecord.fromJson(Map<String, dynamic> json) {
    return DepartmentRecord(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      sessionIntervalMinutes:
          (json['sessionIntervalMinutes'] as num).toInt(),
      active: json['active'] as bool? ?? true,
      checkpointCount: (json['checkpointCount'] as num?)?.toInt() ?? 0,
    );
  }
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

  factory CheckpointRecord.fromJson(Map<String, dynamic> json) {
    return CheckpointRecord(
      id: (json['id'] as num).toInt(),
      departmentId: (json['departmentId'] as num).toInt(),
      name: json['name'] as String,
      nfcUid: json['nfcUid'] as String,
      position: (json['position'] as num).toInt(),
      active: json['active'] as bool? ?? true,
    );
  }
}

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  String? _sessionToken;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool jsonBody = false}) {
    return {
      if (jsonBody) 'Content-Type': 'application/json',
      if (_sessionToken != null) 'Authorization': 'Bearer $_sessionToken',
    };
  }

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
    final data = _decode(response);
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    try {
      await http.post(_uri('/api/auth/logout'), headers: _headers());
    } finally {
      _sessionToken = null;
    }
  }

  Future<PatrolConfig> getPatrolConfig() async {
    final response = await http.get(
      _uri('/api/patrol/config'),
      headers: _headers(),
    );
    return PatrolConfig.fromJson(_decode(response));
  }

  Future<NfcLog> storeNfcScan(String uid) async {
    final response = await http.post(
      _uri('/api/scans'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'nfcUid': uid}),
    );
    final data = _decode(response);
    return NfcLog.fromJson(data['scan'] as Map<String, dynamic>);
  }

  Future<HistoryDay> getHistory(DateTime date) async {
    final response = await http.get(
      _uri('/api/scans', {'date': _dateKey(date)}),
      headers: _headers(),
    );
    return HistoryDay.fromJson(_decode(response));
  }

  Future<AppUser> updateProfilePicture(String dataUrl) async {
    final response = await http.post(
      _uri('/api/profile/picture'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'profilePicture': dataUrl}),
    );
    final data = _decode(response);
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<List<AppUser>> getAdminUsers() async {
    final response = await http.get(
      _uri('/api/admin/users'),
      headers: _headers(),
    );
    final data = _decode(response);
    final users = data['users'] as List<dynamic>? ?? const [];
    return users
        .map((item) => AppUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AppUser> createAdminUser({
    required String nama,
    required String noKadPengenalan,
    required String jawatan,
    required int departmentId,
  }) async {
    final response = await http.post(
      _uri('/api/admin/users'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'nama': nama,
        'noKadPengenalan': noKadPengenalan,
        'jawatan': jawatan,
        'departmentId': departmentId,
      }),
    );
    final data = _decode(response);
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getAdminReport(
    DateTime from,
    DateTime to,
  ) async {
    final response = await http.get(
      _uri('/api/admin/reports', {
        'from': _dateKey(from),
        'to': _dateKey(to),
      }),
      headers: _headers(),
    );
    return _decode(response);
  }

  Future<void> createSos({String? note}) async {
    final response = await http.post(
      _uri('/api/sos'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'note': note}),
    );
    _decode(response);
  }

  Future<List<DepartmentRecord>> getAdminDepartments() async {
    final response = await http.get(
      _uri('/api/admin/departments'),
      headers: _headers(),
    );
    final data = _decode(response);
    final rows = data['departments'] as List<dynamic>? ?? const [];
    return rows
        .map((item) => DepartmentRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<DepartmentRecord> createDepartment({
    required String name,
    required int sessionIntervalMinutes,
  }) async {
    final response = await http.post(
      _uri('/api/admin/departments'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'name': name,
        'sessionIntervalMinutes': sessionIntervalMinutes,
      }),
    );
    final data = _decode(response);
    return DepartmentRecord.fromJson(
      data['department'] as Map<String, dynamic>,
    );
  }

  Future<DepartmentRecord> updateDepartment(DepartmentRecord department) async {
    final response = await http.put(
      _uri('/api/admin/departments/${department.id}'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'name': department.name,
        'sessionIntervalMinutes': department.sessionIntervalMinutes,
        'active': department.active,
      }),
    );
    final data = _decode(response);
    return DepartmentRecord.fromJson(
      data['department'] as Map<String, dynamic>,
    );
  }

  Future<List<CheckpointRecord>> getAdminCheckpoints(int departmentId) async {
    final response = await http.get(
      _uri('/api/admin/checkpoints', {
        'departmentId': departmentId.toString(),
      }),
      headers: _headers(),
    );
    final data = _decode(response);
    final rows = data['checkpoints'] as List<dynamic>? ?? const [];
    return rows
        .map((item) => CheckpointRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CheckpointRecord> createCheckpoint({
    required int departmentId,
    required String name,
    required String nfcUid,
    required int position,
  }) async {
    final response = await http.post(
      _uri('/api/admin/checkpoints'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'departmentId': departmentId,
        'name': name,
        'nfcUid': nfcUid,
        'position': position,
      }),
    );
    final data = _decode(response);
    return CheckpointRecord.fromJson(
      data['checkpoint'] as Map<String, dynamic>,
    );
  }

  Future<CheckpointRecord> updateCheckpoint(CheckpointRecord checkpoint) async {
    final response = await http.put(
      _uri('/api/admin/checkpoints/${checkpoint.id}'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'departmentId': checkpoint.departmentId,
        'name': checkpoint.name,
        'nfcUid': checkpoint.nfcUid,
        'position': checkpoint.position,
        'active': checkpoint.active,
      }),
    );
    final data = _decode(response);
    return CheckpointRecord.fromJson(
      data['checkpoint'] as Map<String, dynamic>,
    );
  }

  Future<AppUser> updateUserDepartment(int userId, int departmentId) async {
    final response = await http.put(
      _uri('/api/admin/users/$userId/department'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'departmentId': departmentId}),
    );
    final data = _decode(response);
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  String _dateKey(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      data = jsonDecode(response.body) as Map<String, dynamic>;
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
