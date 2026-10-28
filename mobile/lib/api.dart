import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String code;
  final String details;
  ApiException(this.code, [this.details = '']);
  @override
  String toString() => details.isEmpty ? code : '$code: $details';
}

class Api {
  static const defaultBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8100',
  );
  Api({http.Client? client, this.base = defaultBase})
    : client = client ?? http.Client();
  final http.Client client;
  final String base;
  final storage = const FlutterSecureStorage();
  String? token;

  /// True when an expired guest session had to be replaced; its data is no longer reachable.
  bool sessionReplaced = false;
  Future<void> init() async {
    token = await storage.read(key: 'session');
    if (token == null) return newSession();
    try {
      // Sliding renewal: every launch extends the 90-day guest session.
      final data = await request('POST', '/v1/guest-sessions/refresh');
      await saveToken(data['token']);
    } on ApiException catch (e) {
      if (e.code != 'session_expired') rethrow;
      sessionReplaced = true;
      await newSession();
    }
  }

  Future<void> newSession() async {
    token = null;
    final data = await request('POST', '/v1/guest-sessions');
    await saveToken(data['token']);
  }

  Future<void> saveToken(String value) async {
    token = value;
    await storage.write(key: 'session', value: value);
  }

  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = http.Request(method, Uri.parse('$base$path'));
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 30)),
    );
    dynamic data;
    try {
      data = response.body.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      // e.g. an HTML error page from a reverse proxy
      if (response.statusCode < 400) throw ApiException('invalid_response');
    }
    if (response.statusCode >= 400) {
      final error = data is Map && data['error'] is Map ? data['error'] : {};
      throw ApiException(
        (error['code'] ?? 'error').toString(),
        (error['details'] ?? '').toString(),
      );
    }
    return data;
  }
}
