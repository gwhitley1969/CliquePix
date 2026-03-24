import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'photos_providers.dart';

class ReactionBarWidget extends ConsumerStatefulWidget {
  final String photoId;
  final Map<String, int> reactionCounts;
  final List<String> userReactions;

  const ReactionBarWidget({
    super.key,
    required this.photoId,
    required this.reactionCounts,
    required this.userReactions,
  });

  @override
  ConsumerState<ReactionBarWidget> createState() => _ReactionBarWidgetState();
}

class _ReactionBarWidgetState extends ConsumerState<ReactionBarWidget> {
  late Map<String, int> _counts;
  late Set<String> _userReactions;

  @override
  void initState() {
    super.initState();
    _counts = Map.from(widget.reactionCounts);
    _userReactions = Set.from(widget.userReactions);
  }

  void _toggleReaction(String type) async {
    final repo = ref.read(photosRepositoryProvider);
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
        // TODO: Need reaction ID for removal — would need to track it
        // For now this is a simplified version
        await repo.removeReaction(widget.photoId, type);
      } else {
        await repo.addReaction(widget.photoId, type);
      }
    } catch (_) {
      // Revert on failure
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? AppColors.deepBlue.withOpacity(0.1) : AppColors.softAquaBackground,
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
