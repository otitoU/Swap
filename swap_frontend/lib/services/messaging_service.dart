import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/conversation.dart';

/// Service for messaging API calls.
class MessagingService {
  final String baseUrl;

  MessagingService({String? baseUrl})
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

  /// Get all conversations for a user.
  Future<ConversationListResponse> getConversations(
    String uid, {
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/conversations').replace(
      queryParameters: {
        'uid': uid,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );

    debugPrint('MessagingService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get conversations: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ConversationListResponse.fromJson(data);
  }

  /// Get a single conversation by ID.
  Future<Conversation> getConversation(String conversationId, String uid) async {
    final uri = Uri.parse('$baseUrl/conversations/$conversationId').replace(
      queryParameters: {'uid': uid},
    );

    debugPrint('MessagingService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get conversation: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Conversation.fromJson(data);
  }

  /// Get messages in a conversation.
  Future<List<Message>> getMessages(
    String conversationId,
    String uid, {
    int limit = 50,
    DateTime? before,
  }) async {
    final queryParams = <String, String>{
      'uid': uid,
      'limit': limit.toString(),
    };
    if (before != null) {
      queryParams['before'] = before.toIso8601String();
    }

    final uri = Uri.parse('$baseUrl/conversations/$conversationId/messages')
        .replace(queryParameters: queryParams);

    debugPrint('MessagingService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get messages: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Send a message in a conversation.
  Future<Message> sendMessage(
    String conversationId,
    String uid,
    String content,
  ) async {
    final uri = Uri.parse('$baseUrl/conversations/$conversationId/messages')
        .replace(queryParameters: {'uid': uid});

    debugPrint('MessagingService: POST $uri');

    final headers = await _getHeaders();
    final response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode({'content': content}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to send message: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Message.fromJson(data);
  }

  /// Mark all messages in a conversation as read.
  Future<void> markConversationRead(String conversationId, String uid) async {
    final uri = Uri.parse('$baseUrl/conversations/$conversationId/mark-read')
        .replace(queryParameters: {'uid': uid});

    debugPrint('MessagingService: POST $uri');

    final headers = await _getHeaders();
    final response = await http.post(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to mark as read: ${response.statusCode} ${response.reasonPhrase}');
    }
  }

  /// Get total unread message count across all conversations.
  Future<int> getTotalUnreadCount(String uid) async {
    final uri = Uri.parse('$baseUrl/conversations/unread-count').replace(
      queryParameters: {'uid': uid},
    );

    debugPrint('MessagingService: GET $uri');

    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get unread count: ${response.statusCode} ${response.reasonPhrase}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['total_unread'] as int? ?? 0;
  }
}
