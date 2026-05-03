import 'package:flutter/material.dart';

import 'loading_shimmer.dart';

// Lightweight shimmer placeholder used on Home only when the user has no
// cached events AND no fresh data yet — i.e. the very first launch after
// signup. Three card-shaped rows pulsing slowly using the shared
// `LoadingShimmer` primitive (already in `widgets/loading_shimmer.dart`).

class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.cardCount = 3});

  final int cardCount;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, __) => const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: LoadingShimmer(height: 132, borderRadius: 16),
        ),
        childCount: cardCount,
      ),
    );
  }
}
