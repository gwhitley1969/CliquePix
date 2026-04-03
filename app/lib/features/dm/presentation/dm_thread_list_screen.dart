import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/error_widget.dart';
import '../../events/presentation/events_providers.dart';
import 'dm_providers.dart';

class DmThreadListScreen extends ConsumerWidget {
  final String eventId;
  const DmThreadListScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(dmThreadsProvider(eventId));
    final eventAsync = ref.watch(eventDetailProvider(eventId));

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1525),
        foregroundColor: Colors.white,
        title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: threadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.electricAqua)),
        error: (err, _) => AppErrorWidget(message: err.toString()),
        data: (threads) {
          if (threads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
                      child: const Icon(Icons.message_outlined, size: 56, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No messages yet',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Start a conversation with an event member',
                      style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            itemCount: threads.length,
            itemBuilder: (context, index) {
              final thread = threads[index];
              final hasUnread = thread.unreadCount > 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.push('/events/$eventId/dm/${thread.id}'),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: hasUnread
                            ? AppColors.electricAqua.withValues(alpha: 0.06)
                            : Colors.white.withValues(alpha: 0.03),
                        border: Border.all(
                          color: hasUnread
                              ? AppColors.electricAqua.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Row(
                        children: [
                          AvatarWidget(name: thread.otherUserName, size: 44),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  thread.otherUserName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                                if (thread.lastMessagePreview != null) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    thread.lastMessagePreview!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white.withValues(alpha: hasUnread ? 0.6 : 0.35),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (thread.lastMessageAt != null)
                                Text(
                                  AppDateUtils.timeAgo(thread.lastMessageAt!),
                                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)),
                                ),
                              if (hasUnread) ...[
                                const SizedBox(height: 6),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.electricAqua,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepBlue.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () {
            final circleId = eventAsync.valueOrNull?.circleId ?? '';
            context.push('/events/$eventId/dm/new?circleId=$circleId');
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
          label: const Text(
            'New Message',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
