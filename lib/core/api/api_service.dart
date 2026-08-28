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
  const NfcLog({required this.id, required this.nfcUid, required this.scannedAt});

  final int? id;
  final String nfcUid;
  final DateTime scannedAt;

  factory NfcLog.fromJson(Map<String, dynamic> json) {
    return NfcLog(
      id: (json['id'] as num?)?.toInt(),
      nfcUid: (json['nfc_uid'] ?? json['nfcUid']) as String,
      scannedAt: DateTime.parse((json['scanned_at'] ?? json['scannedAt']) as String),
    );
  }
}

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  String? _sessionToken;

  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

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

  Future<NfcLog> storeNfcScan(String uid) async {
    final response = await http.post(
      _uri('/api/scans'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'nfcUid': uid}),
    );
    final data = _decode(response);
    return NfcLog.fromJson(data['scan'] as Map<String, dynamic>);
  }

  Future<List<NfcLog>> getScans() async {
    final response = await http.get(_uri('/api/scans'), headers: _headers());
    final data = _decode(response);
    final scans = data['scans'] as List<dynamic>? ?? const [];
    return scans
        .map((item) => NfcLog.fromJson(item as Map<String, dynamic>))
        .toList();
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
