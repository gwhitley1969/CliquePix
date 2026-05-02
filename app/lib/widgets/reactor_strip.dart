import 'package:flutter/material.dart';
import '../models/reactor_model.dart';
import 'avatar_widget.dart';

/// Compact "who reacted?" affordance rendered above the reaction pill row
/// on photo and video cards. Shows up to 3 distinct most-recent reactor
/// avatars overlapping into a small stack, followed by "N reactions"
/// text. Tappable.
///
/// Renders nothing (zero-height) when [totalReactions] is 0 — the parent
/// can include this widget unconditionally and it stays out of the way
/// when no one has reacted yet.
class ReactorStrip extends StatelessWidget {
  final int totalReactions;
  final List<ReactorAvatar> topReactors;
  final VoidCallback onTap;

  const ReactorStrip({
    super.key,
    required this.totalReactions,
    required this.topReactors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (totalReactions <= 0) return const SizedBox.shrink();

    final label = totalReactions == 1 ? '1 reaction' : '$totalReactions reactions';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (topReactors.isNotEmpty) _AvatarStack(reactors: topReactors),
            if (topReactors.isNotEmpty) const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Up to 3 mini-avatars overlapping into a horizontal stack. The leftmost
/// avatar is the most-recent reactor (matches the order returned by the
/// backend's top_reactors query).
class _AvatarStack extends StatelessWidget {
  static const double _avatarSize = 22;
  static const double _overlap = 8; // px of horizontal overlap

  final List<ReactorAvatar> reactors;

  const _AvatarStack({required this.reactors});

  @override
  Widget build(BuildContext context) {
    final visible = reactors.take(3).toList();
    final stackWidth = _avatarSize + (visible.length - 1) * (_avatarSize - _overlap);

    return SizedBox(
      width: stackWidth,
      height: _avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < visible.length; i++)
            Positioned(
              left: i * (_avatarSize - _overlap),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Dark border separates overlapping avatars cleanly against
                  // the dark card surface (matches the card body color used
                  // throughout the app — see CLAUDE.md design tokens).
                  border: Border.all(
                    color: const Color(0xFF1A2035),
                    width: 1.5,
                  ),
                ),
                child: AvatarWidget(
                  imageUrl: visible[i].avatarUrl,
                  thumbUrl: visible[i].avatarThumbUrl,
                  name: visible[i].displayName,
                  size: _avatarSize,
                  framePreset: visible[i].avatarFramePreset,
                  cacheKey: visible[i].avatarCacheKey,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
