import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/points.dart';

/// Service for points API calls.
class PointsService {
  final String baseUrl;

  PointsService({String? baseUrl}) : baseUrl = baseUrl ?? 'http://localhost:8000';

  /// Get authorization headers if user is signed in.
  Future<Map<String, String>> _getHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !kIsWeb) {
        final idToken = await user.getIdToken();
        if (idToken != null) {
          headers['Authorization'] = 'Bearer $idToken';
        }
      }
    } catch (_) {
      // Ignore token errors
    }

    return headers;
  }

  /// Get user's current points balance.
  Future<PointsBalanceResponse> getBalance(
    String uid, {
    bool includeTransactions = true,
    int transactionLimit = 10,
  }) async {
    final uri = Uri.parse('$baseUrl/points/balance/$uid').replace(
      queryParameters: {
        'include_transactions': includeTransactions.toString(),
        'transaction_limit': transactionLimit.toString(),
      },
    );

    debugPrint('PointsService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get points balance: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return PointsBalanceResponse.fromJson(data);
  }

  /// Get points transaction history.
  Future<Map<String, dynamic>> getTransactionHistory(
    String uid, {
    int limit = 20,
    int offset = 0,
    String? typeFilter,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (typeFilter != null) {
      queryParams['type_filter'] = typeFilter;
    }

    final uri = Uri.parse('$baseUrl/points/transactions/$uid')
        .replace(queryParameters: queryParams);

    debugPrint('PointsService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get transaction history: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'transactions': (data['transactions'] as List<dynamic>?)
              ?.map(
                  (e) => PointsTransaction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      'total': data['total'] as int? ?? 0,
      'limit': data['limit'] as int? ?? limit,
      'offset': data['offset'] as int? ?? offset,
      'has_more': data['has_more'] as bool? ?? false,
    };
  }

  /// Spend points on platform features.
  Future<Map<String, dynamic>> spendPoints({
    required String uid,
    required String reason,
    int? durationHours,
  }) async {
    final uri = Uri.parse('$baseUrl/points/spend')
        .replace(queryParameters: {'uid': uid});

    debugPrint('PointsService: POST $uri (reason: $reason)');

    final headers = await _getHeaders();
    final body = jsonEncode({
      'reason': reason,
      if (durationHours != null) 'duration_hours': durationHours,
    });

    final response = await http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final errorBody = response.body;
      throw Exception('Failed to spend points: ${response.statusCode} $errorBody');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'success': data['success'] as bool? ?? false,
      'new_balance': data['new_balance'] as int? ?? 0,
      'transaction_id': data['transaction_id'] as String?,
      'message': data['message'] as String?,
    };
  }

  /// Purchase a priority boost.
  Future<Map<String, dynamic>> purchasePriorityBoost(
      String uid, int durationHours) async {
    return spendPoints(
      uid: uid,
      reason: 'priority_boost',
      durationHours: durationHours,
    );
  }

  /// Purchase the ability to request help without reciprocity.
  Future<Map<String, dynamic>> purchaseRequestWithoutReciprocity(
      String uid) async {
    return spendPoints(uid: uid, reason: 'request_without_reciprocity');
  }

  /// Get active priority boosts for a user.
  Future<Map<String, dynamic>> getActiveBoosts(String uid) async {
    final uri = Uri.parse('$baseUrl/points/active-boosts/$uid');

    debugPrint('PointsService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get active boosts: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'uid': data['uid'] as String?,
      'active_boosts': (data['active_boosts'] as List<dynamic>?)
              ?.map((e) => ActiveBoost.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      'has_active_boost': data['has_active_boost'] as bool? ?? false,
    };
  }
}
