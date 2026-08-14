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

      String targetDb = db;
      if (targetDb.isEmpty) {
        try {
          final dbResponse = await dio.post(
            '$hostUrl/web/database/list',
            data: {
              'jsonrpc': '2.0',
              'params': {},
            },
          );
          dynamic dbPayload = dbResponse.data;
          if (dbPayload is String) dbPayload = jsonDecode(dbPayload);
          final dbList = dbPayload?['result'];
          if (dbList is List && dbList.isNotEmpty) {
            targetDb = dbList.first.toString();
          }
        } catch (e) {
          debugPrint('Could not auto-fetch Odoo db list: $e');
        }
      }

      final Map<String, dynamic> params = {
        'db': targetDb,
        'login': login,
        'password': password,
      };

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

  static Future<Map<String, dynamic>> fetchOdooMetrics({
    required String hostUrl,
    required String sessionId,
  }) async {
    String cleanHost = hostUrl.replaceAll(RegExp(r'/web/?$'), '');
    if (cleanHost.endsWith('/')) {
      cleanHost = cleanHost.substring(0, cleanHost.length - 1);
    }
    debugPrint('fetchOdooMetrics connecting to: $cleanHost/web/dataset/call_kw with session_id=$sessionId');

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          Headers.contentTypeHeader: Headers.jsonContentType,
          'Cookie': 'session_id=$sessionId',
        },
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

    Future<int> getCount(String model, [List domain = const []]) async {
      try {
        final res = await dio.post(
          '$cleanHost/web/dataset/call_kw',
          data: {
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'model': model,
              'method': 'search_count',
              'args': [domain],
              'kwargs': {},
            },
          },
        );
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is Map && data.containsKey('result') && data['result'] is int) {
          final count = data['result'] as int;
          debugPrint('Odoo model $model count: $count');
          return count;
        }
      } catch (e) {
        debugPrint('Error fetching count for $model: $e');
      }
      return 0;
    } 

    Future<List<Map<String, dynamic>>> getRecentLeads() async {
      try {
        final res = await dio.post(
          '$cleanHost/web/dataset/call_kw',
          data: {
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'model': 'crm.lead',
              'method': 'search_read',
              'args': [[]],
              'kwargs': {
                'fields': ['name', 'partner_name', 'contact_name', 'stage_id', 'create_date'],
                'limit': 5,
                'order': 'create_date desc',
              },
            },
          },
        );
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is Map && data['result'] is List) {
          return List<Map<String, dynamic>>.from(data['result']);
        }
      } catch (e) {
        debugPrint('Error fetching recent leads: $e');
      }
      return [];
    }

    final leadsCount = await getCount('crm.lead');
    final partnersCount = await getCount('res.partner');
    final salesCount = await getCount('sale.order');
    final usersCount = await getCount('res.users');
    final tasksCount = await getCount('project.task');
    final recentLeads = await getRecentLeads();

    return {
      'leadsCount': leadsCount,
      'partnersCount': partnersCount > 0 ? partnersCount : usersCount,
      'salesCount': salesCount,
      'usersCount': usersCount,
      'tasksCount': tasksCount,
      'recentLeads': recentLeads,
    };
  }
}
