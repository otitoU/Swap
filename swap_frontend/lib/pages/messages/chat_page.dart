import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../home_page.dart';
import '../../models/conversation.dart';
import '../../services/messaging_service.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/message_input.dart';

/// Page for a single chat conversation.
class ChatPage extends StatefulWidget {
  final Conversation conversation;

  const ChatPage({super.key, required this.conversation});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messagingService = MessagingService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _pollTimer;

  String get _currentUid => FirebaseAuth.instance.currentUser!.uid;

  String get _otherUid => widget.conversation.participantUids
      .firstWhere((uid) => uid != _currentUid, orElse: () => '');

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _markAsRead();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadMessages(silent: true),
    );
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final messages = await _messagingService.getMessages(
        widget.conversation.id,
        _currentUid,
      );
      if (mounted) {
        setState(() {
          // Messages come newest first, reverse for display
          _messages = messages.reversed.toList();
          _loading = false;
        });

        // Scroll to bottom if not silent refresh
        if (!silent) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _markAsRead() async {
    try {
      await _messagingService.markConversationRead(
        widget.conversation.id,
        _currentUid,
      );
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      final message = await _messagingService.sendMessage(
        widget.conversation.id,
        _currentUid,
        content,
      );

      if (mounted) {
        setState(() {
          _messages.add(message);
          _messageController.clear();
          _sending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'block':
        _showBlockDialog();
        break;
      case 'report':
        _showReportDialog();
        break;
    }
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HomePage.surface,
        title: const Text(
          'Block User',
          style: TextStyle(color: HomePage.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to block this user? You won\'t be able to message each other anymore.',
          style: TextStyle(color: HomePage.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement block functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User blocked')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HomePage.surface,
        title: const Text(
          'Report User',
          style: TextStyle(color: HomePage.textPrimary),
        ),
        content: const Text(
          'Report this user for inappropriate behavior? Our team will review the report.',
          style: TextStyle(color: HomePage.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement report functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report submitted')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final other = widget.conversation.otherParticipant;
    final displayName = other?.displayName ?? 'User';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: HomePage.bg,
      appBar: AppBar(
        backgroundColor: HomePage.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: HomePage.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: other?.photoUrl != null && other!.photoUrl!.isNotEmpty
                  ? NetworkImage(other.photoUrl!)
                  : null,
              backgroundColor: HomePage.surfaceAlt,
              child: other?.photoUrl == null || other!.photoUrl!.isEmpty
                  ? Text(
                      initial,
                      style: const TextStyle(
                        color: HomePage.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: HomePage.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (other?.skillsToOffer != null) ...[
                  Text(
                    other!.skillsToOffer!.length > 30
                        ? '${other.skillsToOffer!.substring(0, 30)}...'
                        : other.skillsToOffer!,
                    style: const TextStyle(
                      color: HomePage.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            icon: const Icon(Icons.more_vert, color: HomePage.textMuted),
            color: HomePage.surface,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Block User', style: TextStyle(color: HomePage.textPrimary)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text('Report', style: TextStyle(color: HomePage.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          MessageInput(
            controller: _messageController,
            onSend: _sendMessage,
            sending: _sending,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: HomePage.accent),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: HomePage.textMuted),
            const SizedBox(height: 16),
            Text(
              'Error loading messages',
              style: const TextStyle(color: HomePage.textPrimary),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadMessages,
              style: ElevatedButton.styleFrom(backgroundColor: HomePage.accent),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'No messages yet. Say hello!',
          style: TextStyle(color: HomePage.textMuted),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final message = _messages[i];
        final isMe = message.senderUid == _currentUid;
        final isLast = i == _messages.length - 1;

        return MessageBubble(
          message: message,
          isMe: isMe,
          showReadReceipt: isMe && isLast,
        );
      },
    );
  }
}
