import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalSessionVault {
  LocalSessionVault._();

  static final LocalSessionVault instance = LocalSessionVault._();

  static const _tokenKey = 'rimbakawal_session_token_v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
