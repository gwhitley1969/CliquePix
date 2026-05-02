import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Media-agnostic reaction row. Receives two async callbacks so the same
/// widget can drive photo reactions and video reactions without coupling
/// to either repository.
///
/// Tap a pill = toggle the user's reaction (existing behavior, unchanged).
/// Long-press a pill with count > 0 = call [onShowReactors] with that
/// reaction type. Used by photo/video cards to open the "who reacted?"
/// sheet pre-filtered to that reaction. Default null = long-press is a
/// no-op (backwards compatible with screens that don't surface the sheet).
class ReactionBarWidget extends StatefulWidget {
  final String mediaId;
  final Map<String, int> reactionCounts;
  final List<({String id, String type})> userReactions;
  final Future<({String id, String type})> Function(String reactionType) onAdd;
  final Future<void> Function(String reactionId) onRemove;
  final void Function(String reactionType)? onShowReactors;

  const ReactionBarWidget({
    super.key,
    required this.mediaId,
    required this.reactionCounts,
    required this.userReactions,
    required this.onAdd,
    required this.onRemove,
    this.onShowReactors,
  });

  @override
  State<ReactionBarWidget> createState() => _ReactionBarWidgetState();
}

class _ReactionBarWidgetState extends State<ReactionBarWidget> {
  late Map<String, int> _counts;
  late Set<String> _userReactions;
  late Map<String, String> _userReactionIds; // type -> id

  @override
  void initState() {
    super.initState();
    _counts = Map.from(widget.reactionCounts);
    _userReactionIds = {};
    for (final r in widget.userReactions) {
      _userReactionIds[r.type] = r.id;
    }
    _userReactions = Set.from(_userReactionIds.keys);
  }

  void _toggleReaction(String type) async {
    final wasActive = _userReactions.contains(type);

    // Optimistic update
    setState(() {
      if (wasActive) {
        _userReactions.remove(type);
        _counts[type] = (_counts[type] ?? 1) - 1;
        if (_counts[type]! <= 0) _counts.remove(type);
      } else {
        _userReactions.add(type);
        _counts[type] = (_counts[type] ?? 0) + 1;
      }
    });

    try {
      if (wasActive) {
        final reactionId = _userReactionIds[type];
        if (reactionId != null && reactionId.isNotEmpty) {
          await widget.onRemove(reactionId);
          if (mounted) {
            setState(() => _userReactionIds.remove(type));
          }
        }
      } else {
        final result = await widget.onAdd(type);
        if (mounted) {
          // Capture the id so a subsequent unlike can DELETE correctly.
          setState(() => _userReactionIds[type] = result.id);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasActive) {
          _userReactions.add(type);
          _counts[type] = (_counts[type] ?? 0) + 1;
        } else {
          _userReactions.remove(type);
          _counts[type] = (_counts[type] ?? 1) - 1;
          if (_counts[type]! <= 0) _counts.remove(type);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: AppConstants.reactionTypes.map((type) {
        final emoji = AppConstants.reactionEmojis[type] ?? '';
        final count = _counts[type] ?? 0;
        final isActive = _userReactions.contains(type);

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => _toggleReaction(type),
            // Long-press only fires when the pill has at least one
            // reaction AND the host screen wired a sheet handler. Empty
            // pills + screens without onShowReactors fall through to a
            // no-op so existing callsites keep working unchanged.
            onLongPress: (widget.onShowReactors != null && (_counts[type] ?? 0) > 0)
                ? () {
                    HapticFeedback.mediumImpact();
                    widget.onShowReactors!(type);
                  }
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? AppColors.deepBlue.withValues(alpha: 0.1) : AppColors.softAquaBackground,
                borderRadius: BorderRadius.circular(20),
                border: isActive ? Border.all(color: AppColors.deepBlue, width: 1.5) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        color: isActive ? AppColors.deepBlue : AppColors.secondaryText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
