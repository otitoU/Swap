import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/swap_request.dart';

/// Service for swap request API calls.
class SwapRequestService {
  final String baseUrl;

  SwapRequestService({String? baseUrl})
      : baseUrl = baseUrl ?? 'http://localhost:8000';

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

  /// Create a new swap request.
  Future<SwapRequest> createRequest({
    required String requesterUid,
    required String recipientUid,
    required String requesterOffer,
    required String requesterNeed,
    String? message,
  }) async {
    final uri = Uri.parse('$baseUrl/swap-requests').replace(
      queryParameters: {'requester_uid': requesterUid},
    );

    debugPrint('SwapRequestService: POST $uri');

    final headers = await _getHeaders();
    final body = jsonEncode({
      'recipient_uid': recipientUid,
      'requester_offer': requesterOffer,
      'requester_need': requesterNeed,
      if (message != null && message.isNotEmpty) 'message': message,
    });

    final response = await http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final errorBody = response.body;
      throw Exception(
          'Failed to create swap request: ${response.statusCode} $errorBody');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return SwapRequest.fromJson(data);
  }

  /// Get incoming swap requests (sent TO the user).
  Future<List<SwapRequest>> getIncomingRequests(
    String uid, {
    SwapRequestStatus? status,
  }) async {
    final queryParams = <String, String>{'uid': uid};
    if (status != null) {
      queryParams['status'] = status.name;
    }

    final uri = Uri.parse('$baseUrl/swap-requests/incoming')
        .replace(queryParameters: queryParams);

    debugPrint('SwapRequestService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get incoming requests: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => SwapRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get outgoing swap requests (sent BY the user).
  Future<List<SwapRequest>> getOutgoingRequests(
    String uid, {
    SwapRequestStatus? status,
  }) async {
    final queryParams = <String, String>{'uid': uid};
    if (status != null) {
      queryParams['status'] = status.name;
    }

    final uri = Uri.parse('$baseUrl/swap-requests/outgoing')
        .replace(queryParameters: queryParams);

    debugPrint('SwapRequestService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get outgoing requests: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => SwapRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Respond to a swap request (accept or decline).
  Future<SwapRequest> respondToRequest(
    String requestId,
    String uid,
    bool accept,
  ) async {
    final uri = Uri.parse('$baseUrl/swap-requests/$requestId/respond')
        .replace(queryParameters: {'uid': uid});

    debugPrint('SwapRequestService: POST $uri (accept: $accept)');

    final headers = await _getHeaders();
    final body = jsonEncode({
      'action': accept ? 'accept' : 'decline',
    });

    final response = await http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to respond to request: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return SwapRequest.fromJson(data);
  }

  /// Cancel a pending swap request.
  Future<void> cancelRequest(String requestId, String uid) async {
    final uri = Uri.parse('$baseUrl/swap-requests/$requestId')
        .replace(queryParameters: {'uid': uid});

    debugPrint('SwapRequestService: DELETE $uri');

    final headers = await _getHeaders();
    final response = await http.delete(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to cancel request: ${response.statusCode} ${response.reasonPhrase}');
    }
  }

  /// Get a specific swap request by ID.
  Future<SwapRequest> getRequest(String requestId, String uid) async {
    final uri = Uri.parse('$baseUrl/swap-requests/$requestId')
        .replace(queryParameters: {'uid': uid});

    debugPrint('SwapRequestService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get request: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return SwapRequest.fromJson(data);
  }
}
