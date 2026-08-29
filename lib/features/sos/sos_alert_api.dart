import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api/api_service.dart';
import '../../core/offline/local_session_vault.dart';

class SosAlertApi {
  SosAlertApi._();

  static final SosAlertApi instance = SosAlertApi._();

  final LocalSessionVault _vault = LocalSessionVault.instance;

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final token = await _vault.readToken();
    if (token == null || token.isEmpty) {
      throw const ApiException('Sesi tidak sah. Sila log masuk semula.', statusCode: 401);
    }
    return {
      if (jsonBody) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<Map<String, dynamic>>> fetchAlerts() async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/api/sos/alerts'),
      headers: await _headers(),
    );
    final data = _decode(response);
    return (data['alerts'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> acknowledge(int sosId) async {
    _decode(
      await http.post(
        Uri.parse('$apiBaseUrl/api/sos/$sosId/ack'),
        headers: await _headers(jsonBody: true),
        body: '{}',
      ),
    );
  }

  Future<List<Map<String, dynamic>>> fetchManagedEvents() async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/api/sos/manage'),
      headers: await _headers(),
    );
    final data = _decode(response);
    return (data['events'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> resolve(int sosId, String note) async {
    _decode(
      await http.put(
        Uri.parse('$apiBaseUrl/api/sos/$sosId/resolve'),
        headers: await _headers(jsonBody: true),
        body: jsonEncode({'note': note}),
      ),
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      data = const {};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        data['error'] as String? ?? 'Permintaan SOS gagal.',
        statusCode: response.statusCode,
      );
    }
    return data;
  }
}
