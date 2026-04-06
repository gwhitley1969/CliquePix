import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/error_widget.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../cliques/presentation/cliques_providers.dart';
import 'dm_providers.dart';

class DmMemberPickerScreen extends ConsumerWidget {
  final String eventId;
  final String cliqueId;
  const DmMemberPickerScreen({super.key, required this.eventId, required this.cliqueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(cliqueMembersProvider(cliqueId));
    final authState = ref.watch(authStateProvider);
    final currentUserId = authState is AuthAuthenticated ? authState.user.id : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1525),
        foregroundColor: Colors.white,
        title: const Text('New Message', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.electricAqua)),
        error: (err, _) => AppErrorWidget(message: err.toString()),
        data: (members) {
          // Filter out current user
          final otherMembers = members.where((m) => m.userId != currentUserId).toList();

          if (otherMembers.isEmpty) {
            return Center(
              child: Text(
                'No other members in this clique',
                style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.5)),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            itemCount: otherMembers.length,
            itemBuilder: (context, index) {
              final member = otherMembers[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      try {
                        final thread = await ref.read(dmRepositoryProvider)
                            .createOrGetThread(eventId, member.userId);
                        if (context.mounted) {
                          context.pushReplacement('/events/$eventId/dm/${thread.id}');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to start chat: $e'), backgroundColor: const Color(0xFFEF4444)),
                          );
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white.withValues(alpha: 0.03),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          AvatarWidget(name: member.displayName, imageUrl: member.avatarUrl, size: 40),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              member.displayName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white),
                            ),
                          ),
                          ShaderMask(
                            shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
                            child: const Icon(Icons.message_rounded, color: Colors.white, size: 20),
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
    );
  }
}
