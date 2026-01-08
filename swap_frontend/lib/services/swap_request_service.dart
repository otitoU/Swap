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
  /// 
  /// For direct swaps: provide requesterOffer (the skill you're offering).
  /// For indirect swaps: provide pointsOffered (points to pay for the service).
  Future<SwapRequest> createRequest({
    required String requesterUid,
    required String recipientUid,
    required String requesterNeed,
    String? requesterOffer,
    String? message,
    SwapType swapType = SwapType.direct,
    int? pointsOffered,
  }) async {
    final uri = Uri.parse('$baseUrl/swap-requests').replace(
      queryParameters: {'requester_uid': requesterUid},
    );

    debugPrint('SwapRequestService: POST $uri (swapType: ${swapType.name})');

    final headers = await _getHeaders();
    final body = jsonEncode({
      'recipient_uid': recipientUid,
      'requester_need': requesterNeed,
      'swap_type': swapType.name,
      if (requesterOffer != null && requesterOffer.isNotEmpty) 
        'requester_offer': requesterOffer,
      if (message != null && message.isNotEmpty) 
        'message': message,
      if (swapType == SwapType.indirect && pointsOffered != null) 
        'points_offered': pointsOffered,
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

  /// Mark a swap as complete.
  Future<SwapRequest> markComplete({
    required String requestId,
    required String uid,
    required double hoursExchanged,
    required String skillLevel,
    String? notes,
  }) async {
    final uri = Uri.parse('$baseUrl/swaps/$requestId/complete')
        .replace(queryParameters: {'uid': uid});

    debugPrint('SwapRequestService: POST $uri (marking complete with $hoursExchanged hours)');

    final headers = await _getHeaders();
    final body = jsonEncode({
      'hours_exchanged': hoursExchanged,
      'skill_level': skillLevel,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });

    final response = await http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final errorBody = response.body;
      throw Exception(
          'Failed to mark complete: ${response.statusCode} $errorBody');
    }

    // The completion endpoint returns SwapCompletionStatus, but we need
    // the full SwapRequest. Fetch it again to get the updated data.
    return await getRequest(requestId, uid);
  }

  /// Verify or dispute a swap completion.
  Future<SwapRequest> verifyCompletion({
    required String requestId,
    required String uid,
    required bool verify,
    String? disputeReason,
  }) async {
    final uri = Uri.parse('$baseUrl/swaps/$requestId/verify')
        .replace(queryParameters: {'uid': uid});

    debugPrint('SwapRequestService: POST $uri (verify: $verify)');

    final headers = await _getHeaders();
    final body = jsonEncode({
      'action': verify ? 'verify' : 'dispute',
      if (!verify && disputeReason != null) 'dispute_reason': disputeReason,
    });

    final response = await http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final errorBody = response.body;
      throw Exception(
          'Failed to verify completion: ${response.statusCode} $errorBody');
    }

    // The verify endpoint returns SwapCompletionStatus, but we need
    // the full SwapRequest. Fetch it again to get the updated data.
    return await getRequest(requestId, uid);
  }

  /// Get completion status for a swap.
  Future<Map<String, dynamic>> getCompletionStatus(
      String requestId, String uid) async {
    final uri = Uri.parse('$baseUrl/swaps/$requestId/completion-status')
        .replace(queryParameters: {'uid': uid});

    debugPrint('SwapRequestService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get completion status: ${response.statusCode} ${response.reasonPhrase}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Get completed swaps for the user.
  Future<List<SwapRequest>> getCompletedSwaps(String uid,
      {int limit = 20}) async {
    final uri = Uri.parse('$baseUrl/swaps/completed').replace(
      queryParameters: {
        'uid': uid,
        'limit': limit.toString(),
      },
    );

    debugPrint('SwapRequestService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get completed swaps: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final swaps = data['completed_swaps'] as List<dynamic>? ?? [];
    return swaps
        .map((e) => SwapRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
