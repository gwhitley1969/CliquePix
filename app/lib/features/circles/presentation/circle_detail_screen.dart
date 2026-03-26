import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../widgets/error_widget.dart';
import 'circles_providers.dart';

class CircleDetailScreen extends ConsumerWidget {
  final String circleId;
  const CircleDetailScreen({super.key, required this.circleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circleAsync = ref.watch(circleDetailProvider(circleId));
    final membersAsync = ref.watch(circleMembersProvider(circleId));

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1525),
        foregroundColor: Colors.white,
        title: circleAsync.when(
          data: (c) => Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          loading: () => const Text('Circle'),
          error: (_, __) => const Text('Circle'),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => context.go('/circles/$circleId/invite'),
          ),
        ],
      ),
      body: circleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.electricAqua)),
        error: (err, _) => AppErrorWidget(message: err.toString()),
        data: (circle) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Events card
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.go('/circles/$circleId/events'),
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
                      return Column(
                        children: [
                          Padding(
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
                              ],
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
                    onTap: () => context.go('/circles/$circleId/invite'),
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
            ],
          ),
        ),
      ),
    );
  }
}
