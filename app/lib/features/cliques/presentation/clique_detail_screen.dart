import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/confirm_destructive_dialog.dart';
import '../../../widgets/error_widget.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import 'cliques_providers.dart';

class CliqueDetailScreen extends ConsumerStatefulWidget {
  final String cliqueId;
  const CliqueDetailScreen({super.key, required this.cliqueId});

  @override
  ConsumerState<CliqueDetailScreen> createState() => _CliqueDetailScreenState();
}

class _CliqueDetailScreenState extends ConsumerState<CliqueDetailScreen>
    with WidgetsBindingObserver {
  String get cliqueId => widget.cliqueId;
  Timer? _pollTimer;
  bool _navigatingAway = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(cliqueDetailProvider(cliqueId));
      ref.invalidate(cliqueMembersProvider(cliqueId));
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(cliqueDetailProvider(cliqueId));
    ref.invalidate(cliqueMembersProvider(cliqueId));
    await ref.read(cliqueMembersProvider(cliqueId).future);
  }

  Future<void> _showRemoveMemberDialog(String memberName, String memberId) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove Member',
      body: 'Remove $memberName from this clique?',
      confirmLabel: 'Remove',
    );

    if (confirmed && mounted) {
      try {
        await ref.read(cliquesRepositoryProvider).removeMember(cliqueId, memberId);
        ref.invalidate(cliqueMembersProvider(cliqueId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$memberName has been removed'), backgroundColor: const Color(0xFF1A2035)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove member: $e'), backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    }
  }

  Future<void> _showLeaveCliqueDialog(String cliqueName) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Leave Clique',
      body:
          'Leave $cliqueName? You will no longer have access to its events and photos.',
      confirmLabel: 'Leave',
    );

    if (confirmed && mounted) {
      try {
        await ref.read(cliquesRepositoryProvider).leaveClique(cliqueId);
        ref.invalidate(cliquesListProvider);
        if (mounted) context.go('/cliques');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to leave clique: $e'), backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    }
  }

  Future<void> _showDeleteCliqueDialog(String cliqueName) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete Clique',
      body:
          'Delete $cliqueName? This will permanently remove the clique and all its events and photos.',
    );

    if (confirmed && mounted) {
      try {
        await ref.read(cliquesRepositoryProvider).leaveClique(cliqueId);
        ref.invalidate(cliquesListProvider);
        if (mounted) context.go('/cliques');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete clique: $e'), backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cliqueAsync = ref.watch(cliqueDetailProvider(cliqueId));
    final membersAsync = ref.watch(cliqueMembersProvider(cliqueId));

    final authState = ref.watch(authStateProvider);
    final currentUserId = authState is AuthAuthenticated ? authState.user.id : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1525),
        foregroundColor: Colors.white,
        title: cliqueAsync.when(
          data: (c) => Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          loading: () => const Text('Clique'),
          error: (_, __) => const Text('Clique'),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => context.go('/cliques/$cliqueId/invite'),
          ),
        ],
      ),
      body: cliqueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.electricAqua)),
        error: (err, _) {
          if (!_navigatingAway && err is DioException && err.response?.statusCode == 404) {
            _navigatingAway = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ref.invalidate(cliquesListProvider);
                context.go('/cliques');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You are no longer a member of this clique'),
                    backgroundColor: Color(0xFF1A2035),
                  ),
                );
              }
            });
            return const Center(child: CircularProgressIndicator(color: AppColors.electricAqua));
          }
          return AppErrorWidget(message: err.toString());
        },
        data: (clique) {
          final isOwner = clique.createdByUserId == currentUserId;
          final memberCount = membersAsync.valueOrNull?.length ?? clique.memberCount;

          return RefreshIndicator(
            color: AppColors.electricAqua,
            backgroundColor: const Color(0xFF1A2035),
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Events card
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.go('/cliques/$cliqueId/events'),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              AppColors.electricAqua.withValues(alpha: 0.08),
                              AppColors.deepBlue.withValues(alpha: 0.04),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: AppColors.electricAqua.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: const LinearGradient(
                                  colors: [AppColors.electricAqua, AppColors.deepBlue],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Events',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                  Text(
                                    'View and create photo events',
                                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.electricAqua.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: AppColors.electricAqua.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Members section
                  Text(
                    'Members',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 12),
                  membersAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: AppColors.electricAqua),
                      ),
                    ),
                    error: (err, _) => Text(err.toString(), style: const TextStyle(color: AppColors.error)),
                    data: (members) => Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white.withValues(alpha: 0.04),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Column(
                        children: List.generate(members.length, (i) {
                          final m = members[i];
                          final isLast = i == members.length - 1;
                          final canRemove = isOwner && m.userId != currentUserId;
                          return Column(
                            children: [
                              InkWell(
                                onTap: canRemove ? () => _showRemoveMemberDialog(m.displayName, m.userId) : null,
                                borderRadius: isLast
                                    ? const BorderRadius.vertical(bottom: Radius.circular(16))
                                    : i == 0
                                        ? const BorderRadius.vertical(top: Radius.circular(16))
                                        : BorderRadius.zero,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      AvatarWidget(name: m.displayName, imageUrl: m.avatarUrl, size: 40),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              m.displayName,
                                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white),
                                            ),
                                            Text(
                                              m.role == 'owner' ? 'Owner' : 'Member',
                                              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (m.role == 'owner')
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(6),
                                            color: AppColors.violetAccent.withValues(alpha: 0.15),
                                          ),
                                          child: Text(
                                            'Owner',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.violetAccent.withValues(alpha: 0.8),
                                            ),
                                          ),
                                        ),
                                      if (canRemove)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 8),
                                          child: Icon(
                                            Icons.remove_circle_outline,
                                            size: 20,
                                            color: Colors.white.withValues(alpha: 0.2),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (!isLast) Divider(height: 1, indent: 66, color: Colors.white.withValues(alpha: 0.06)),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Invite button
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.deepBlue.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => context.go('/cliques/$cliqueId/invite'),
                        borderRadius: BorderRadius.circular(14),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Invite Friends',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Leave / Delete button
                  if (!isOwner) ...[
                    const SizedBox(height: 16),
                    _buildDestructiveButton(
                      label: 'Leave Clique',
                      icon: Icons.exit_to_app_rounded,
                      onTap: () => _showLeaveCliqueDialog(clique.name),
                    ),
                  ] else if (isOwner && memberCount <= 1) ...[
                    const SizedBox(height: 16),
                    _buildDestructiveButton(
                      label: 'Delete Clique',
                      icon: Icons.delete_outline_rounded,
                      onTap: () => _showDeleteCliqueDialog(clique.name),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDestructiveButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFFEF4444), size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
