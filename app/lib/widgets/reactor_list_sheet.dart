import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../models/reactor_model.dart';
import 'avatar_widget.dart';

/// "Who reacted?" bottom sheet — opens when the user taps a [ReactorStrip]
/// or long-presses a reaction pill. Shows a tab per reaction type that has
/// at least one reactor (plus an "All" tab covering everyone), with rows
/// of avatar + display name + reaction emoji.
///
/// Refetches on every open (no long-lived cache, no cross-screen
/// invalidation needed when the user reacts via the pill).
///
/// Usage:
///   ReactorListSheet.show(
///     context,
///     mediaTitle: 'Reactions',
///     fetchReactors: () => repo.listReactors(media.id),
///     initialFilter: 'heart', // optional; null = open on All tab
///   );
class ReactorListSheet {
  static Future<void> show(
    BuildContext context, {
    required Future<ReactorList> Function() fetchReactors,
    String? initialFilter,
  }) {
    HapticFeedback.selectionClick();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A2035),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ReactorSheetBody(
        fetchReactors: fetchReactors,
        initialFilter: initialFilter,
      ),
    );
  }
}

class _ReactorSheetBody extends StatefulWidget {
  final Future<ReactorList> Function() fetchReactors;
  final String? initialFilter;

  const _ReactorSheetBody({
    required this.fetchReactors,
    required this.initialFilter,
  });

  @override
  State<_ReactorSheetBody> createState() => _ReactorSheetBodyState();
}

class _ReactorSheetBodyState extends State<_ReactorSheetBody> {
  late Future<ReactorList> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchReactors();
  }

  void _retry() {
    setState(() {
      _future = widget.fetchReactors();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            const _DragHandle(),
            const _Header(),
            Expanded(
              child: FutureBuilder<ReactorList>(
                future: _future,
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _SkeletonList();
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return _ErrorState(onRetry: _retry);
                  }
                  return _ReactorTabs(
                    list: snapshot.data!,
                    initialFilter: widget.initialFilter,
                    scrollController: scrollController,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          const Text(
            'Reactions',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: 4,
      itemBuilder: (_, __) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
              ),
              const SizedBox(width: 12),
              Container(
                width: 140,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 36,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load reactions.",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Retry',
                style: TextStyle(color: AppColors.electricAqua),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactorTabs extends StatelessWidget {
  final ReactorList list;
  final String? initialFilter;
  final ScrollController scrollController;

  const _ReactorTabs({
    required this.list,
    required this.initialFilter,
    required this.scrollController,
  });

  /// Tabs shown: "All" first, then one per reaction type that has at
  /// least one reactor, ordered by AppConstants.reactionTypes (heart,
  /// laugh, fire, wow). Empty types are skipped.
  List<({String? filter, String label, int count})> _buildTabs() {
    final tabs = <({String? filter, String label, int count})>[
      (filter: null, label: 'All ${list.totalReactions}', count: list.totalReactions),
    ];
    for (final type in AppConstants.reactionTypes) {
      final count = list.byType[type] ?? 0;
      if (count > 0) {
        final emoji = AppConstants.reactionEmojis[type] ?? '';
        tabs.add((filter: type, label: '$emoji $count', count: count));
      }
    }
    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _buildTabs();
    final initialIdx = initialFilter == null
        ? 0
        : tabs.indexWhere((t) => t.filter == initialFilter).clamp(0, tabs.length - 1);

    return DefaultTabController(
      length: tabs.length,
      initialIndex: initialIdx,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.electricAqua,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            tabs: tabs.map((t) => Tab(text: t.label)).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: tabs.map((tab) {
                final filtered = tab.filter == null
                    ? list.reactors
                    : list.filterByType(tab.filter!);
                if (filtered.isEmpty) {
                  return const _EmptyState();
                }
                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, idx) => _ReactorRow(reactor: filtered[idx]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          "No one's reacted with this yet.",
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ReactorRow extends StatelessWidget {
  final ReactorEntry reactor;
  const _ReactorRow({required this.reactor});

  @override
  Widget build(BuildContext context) {
    final emoji = AppConstants.reactionEmojis[reactor.reactionType] ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          AvatarWidget(
            imageUrl: reactor.avatarUrl,
            thumbUrl: reactor.avatarThumbUrl,
            name: reactor.displayName,
            size: 40,
            framePreset: reactor.avatarFramePreset,
            cacheKey: reactor.avatarCacheKey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              reactor.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(emoji, style: const TextStyle(fontSize: 22)),
        ],
      ),
    );
  }
}
