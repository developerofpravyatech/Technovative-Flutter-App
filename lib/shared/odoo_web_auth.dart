import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// Authenticates against Odoo's standard web session API and returns `session_id`.
/// Used so the in-app WebView can open `/web` already logged in (no second login).
class OdooWebAuth {
  static Future<String?> authenticate({
    required String hostUrl,
    required String db,
    required String login,
    required String password,
  }) async {  
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.json,
          headers: {Headers.contentTypeHeader: Headers.jsonContentType},
        ),
      );

      if (!kIsWeb) {
        (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
            (HttpClient client) {
          client.badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;
          return client;
        };
      }

      final Map<String, dynamic> params = {
        'login': login,
        'password': password,
      };
      if (db.isNotEmpty) {
        params['db'] = db;
      }

      final response = await dio.post(
        '$hostUrl/web/session/authenticate',
        data: {
          'jsonrpc': '2.0',
          'params': params,
        },
      );

      dynamic payload = response.data;
      if (payload is String) {
        payload = jsonDecode(payload);
      }
      if (payload is! Map) {
        debugPrint('Odoo web auth: unexpected payload $payload');
        return null;
      }

      final result = payload['result'];
      if (result is! Map || result['uid'] == null || result['uid'] == false) {
        debugPrint('Odoo web auth failed: $payload');
        return null;
      }

      final setCookies = response.headers.map['set-cookie'] ?? const [];
      for (final raw in setCookies) {
        final match = RegExp(r'session_id=([^;]+)').firstMatch(raw);
        if (match != null) {
          return match.group(1);
        }
      }

      final sessionFromResult = result['session_id'];
      if (sessionFromResult != null) {
        return sessionFromResult.toString();
      }

      debugPrint('Odoo web auth: uid ok but no session_id cookie found');
      return null;
    } catch (e, st) {
      debugPrint('Odoo web auth error: $e');
      debugPrint('$st');
      return null;
    }
  }
}
