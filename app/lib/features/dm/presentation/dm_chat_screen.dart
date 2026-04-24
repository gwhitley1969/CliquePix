import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/dm_message_model.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/error_widget.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import 'dm_providers.dart';

class DmChatScreen extends ConsumerStatefulWidget {
  final String threadId;
  final String eventId;
  const DmChatScreen({super.key, required this.threadId, required this.eventId});

  @override
  ConsumerState<DmChatScreen> createState() => _DmChatScreenState();
}

class _DmChatScreenState extends ConsumerState<DmChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<DmMessageModel> _localMessages = [];
  StreamSubscription? _realtimeSub;
  bool _isSending = false;

  String? get _currentUserId {
    final authState = ref.read(authStateProvider);
    return authState is AuthAuthenticated ? authState.user.id : null;
  }

  @override
  void initState() {
    super.initState();
    _setupRealtime();
  }

  Future<void> _setupRealtime() async {
    try {
      final realtimeService = ref.read(dmRealtimeServiceProvider);
      realtimeService.onNegotiate = () => ref.read(dmRepositoryProvider).negotiate();
      if (!realtimeService.isConnected) {
        final url = await ref.read(dmRepositoryProvider).negotiate();
        await realtimeService.connect(url);
      }
      _realtimeSub = realtimeService.onMessage.listen((message) {
        if (message.threadId == widget.threadId && message.senderUserId != _currentUserId) {
          if (mounted) {
            setState(() => _localMessages.add(message));
            _scrollToBottom();
            // Mark as read
            ref.read(dmRepositoryProvider).markRead(widget.threadId, message.id);
          }
        }
      });
    } catch (e) {
      debugPrint('[CliquePix DM] Realtime setup failed: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final message = await ref.read(dmRepositoryProvider).sendMessage(widget.threadId, body);
      if (mounted) {
        setState(() {
          _localMessages.add(message);
          _isSending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threadAsync = ref.watch(dmThreadDetailProvider(widget.threadId));
    final messagesAsync = ref.watch(dmMessagesProvider(widget.threadId));
    final currentUserId = _currentUserId;

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1525),
        foregroundColor: Colors.white,
        title: threadAsync.when(
          data: (thread) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarWidget(
                name: thread.otherUserName,
                imageUrl: thread.otherUserAvatarUrl,
                thumbUrl: thread.otherUserAvatarThumbUrl,
                cacheKey: thread.otherUserAvatarCacheKey,
                framePreset: thread.otherUserAvatarFramePreset,
                size: 30,
              ),
              const SizedBox(width: 10),
              Text(thread.otherUserName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          loading: () => const Text('Chat'),
          error: (_, __) => const Text('Chat'),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Read-only banner
          threadAsync.when(
            data: (thread) {
              if (thread.isReadOnly) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  color: Colors.white.withValues(alpha: 0.06),
                  child: Text(
                    'This chat is now read-only because the event ended.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Messages
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.electricAqua)),
              error: (err, _) => AppErrorWidget(message: err.toString()),
              data: (serverMessages) {
                // Combine server messages + locally added messages, deduplicate by ID
                final allIds = <String>{};
                final combined = <DmMessageModel>[];
                // Server messages come newest-first, reverse for chronological order
                for (final m in serverMessages.reversed) {
                  if (allIds.add(m.id)) combined.add(m);
                }
                for (final m in _localMessages) {
                  if (allIds.add(m.id)) combined.add(m);
                }

                if (combined.isEmpty) {
                  return Center(
                    child: Text(
                      'Say hello!',
                      style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.4)),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: combined.length,
                  itemBuilder: (context, index) {
                    final message = combined[index];
                    final isMe = message.senderUserId == currentUserId;
                    return _MessageBubble(message: message, isMe: isMe);
                  },
                );
              },
            ),
          ),

          // Composer
          threadAsync.when(
            data: (thread) {
              if (thread.isReadOnly) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF162033),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          maxLines: 4,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Message...',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppGradients.primary,
                        ),
                        child: IconButton(
                          icon: _isSending
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          onPressed: _isSending ? null : _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final DmMessageModel message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isMe) const Spacer(flex: 2),
          Flexible(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                ),
                gradient: isMe
                    ? const LinearGradient(
                        colors: [AppColors.electricAqua, AppColors.deepBlue],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe ? null : Colors.white.withValues(alpha: 0.08),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.body,
                    style: TextStyle(
                      fontSize: 15,
                      color: isMe ? Colors.white : Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppDateUtils.timeAgo(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isMe) const Spacer(flex: 2),
        ],
      ),
    );
  }
}
