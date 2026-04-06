import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../widgets/error_widget.dart';
import '../../../widgets/avatar_widget.dart';
import '../../../models/clique_model.dart';
import 'cliques_providers.dart';

class CliquesListScreen extends ConsumerStatefulWidget {
  const CliquesListScreen({super.key});

  @override
  ConsumerState<CliquesListScreen> createState() => _CliquesListScreenState();
}

class _CliquesListScreenState extends ConsumerState<CliquesListScreen>
    with WidgetsBindingObserver {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.read(cliquesListProvider.notifier).refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(cliquesListProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cliquesAsync = ref.watch(cliquesListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      body: RefreshIndicator(
        color: AppColors.electricAqua,
        backgroundColor: const Color(0xFF1A2035),
        onRefresh: () => ref.read(cliquesListProvider.notifier).refresh(),
        child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Gradient header with brand personality
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF0E1525),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: () => ref.read(cliquesListProvider.notifier).refresh(),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: ShaderMask(
                shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
                child: const Text(
                  'My Cliques',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              centerTitle: true,
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.deepBlue.withValues(alpha: 0.15),
                      const Color(0xFF0E1525),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content
          cliquesAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.electricAqua),
              ),
            ),
            error: (err, _) => SliverFillRemaining(
              child: AppErrorWidget(
                message: err.toString(),
                onRetry: () => ref.read(cliquesListProvider.notifier).refresh(),
              ),
            ),
            data: (cliques) {
              if (cliques.isEmpty) {
                return SliverFillRemaining(
                  child: EmptyStateWidget(
                    icon: Icons.group_outlined,
                    title: 'No cliques yet',
                    subtitle: 'Create a clique to start sharing photos with friends',
                    actionText: 'Create Clique',
                    onAction: () => context.go('/cliques/create'),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _CliqueCard(clique: cliques[index]),
                    childCount: cliques.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
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
          onPressed: () => context.go('/cliques/create'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
          label: const Text(
            'Create Clique',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ),
    );
  }
}

class _CliqueCard extends StatelessWidget {
  final CliqueModel clique;
  const _CliqueCard({required this.clique});

  List<Color> _gradientForName(String name) {
    final hash = name.hashCode.abs() % 5;
    switch (hash) {
      case 0:
        return [AppColors.electricAqua, AppColors.deepBlue];
      case 1:
        return [AppColors.deepBlue, AppColors.violetAccent];
      case 2:
        return [AppColors.violetAccent, const Color(0xFFEC4899)];
      case 3:
        return [AppColors.electricAqua, AppColors.violetAccent];
      default:
        return [const Color(0xFFEC4899), AppColors.electricAqua];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradientForName(clique.name);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.go('/cliques/${clique.id}'),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  colors[0].withValues(alpha: 0.08),
                  colors[1].withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: colors[0].withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AvatarWidget(name: clique.name, size: 54),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clique.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.people_rounded,
                              size: 14,
                              color: colors[0].withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${clique.memberCount} member${clique.memberCount != 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors[0].withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: colors[0].withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
