import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/avatar_widget.dart';

/// A 2-second slow-pulse glow layered behind an empty-state
/// `AvatarWidget`. Draws attention to the tappable gradient ring the
/// first time a user lands on Profile without a headshot. Stops pulsing
/// the moment `imageUrl` becomes non-null.
class AnimatedEmptyAvatar extends StatefulWidget {
  final String name;
  final int framePreset;
  final double size;
  final VoidCallback? onTap;

  const AnimatedEmptyAvatar({
    super.key,
    required this.name,
    this.framePreset = 0,
    this.size = 88,
    this.onTap,
  });

  @override
  State<AnimatedEmptyAvatar> createState() => _AnimatedEmptyAvatarState();
}

class _AnimatedEmptyAvatarState extends State<AnimatedEmptyAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulse = Tween<double>(begin: 0.2, end: 0.55)
              .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut))
              .value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow layer — a slightly larger blurred circle behind
              // the avatar.
              Container(
                width: widget.size + 24,
                height: widget.size + 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.electricAqua.withValues(alpha: pulse),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
              if (child != null) child,
            ],
          );
        },
        child: AvatarWidget(
          name: widget.name,
          size: widget.size,
          framePreset: widget.framePreset,
        ),
      ),
    );
  }
}
