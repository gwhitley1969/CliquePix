import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_gradients.dart';

/// Pinned [SliverAppBar] with the persistent "Clique Pix" brand ribbon
/// (logo + gradient wordmark) in the toolbar and a larger screen-title
/// hero in the flexible area below.
///
/// The brand wordmark always uses [AppGradients.primary] for consistency
/// across tabs. The screen title's gradient and the background accent
/// wash are parameterized per tab.
class BrandedSliverAppBar extends StatelessWidget {
  final String screenTitle;
  final Gradient screenTitleGradient;
  final Color accentColor;
  final double accentOpacity;
  final List<Widget>? actions;

  const BrandedSliverAppBar({
    super.key,
    required this.screenTitle,
    this.screenTitleGradient = AppGradients.primary,
    this.accentColor = AppColors.electricAqua,
    this.accentOpacity = 0.12,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 260,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF0E1525),
      automaticallyImplyLeading: false,
      actions: actions,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Per-tab accent wash — top-tinted, fades to dark surface
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accentColor.withValues(alpha: accentOpacity),
                    const Color(0xFF0E1525),
                  ],
                ),
              ),
            ),
            // Brand wordmark — positioned below status bar with extra top
            // breathing room so it sits where the hero banner reads best.
            const Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _CliquePixWordmark(),
                  ),
                ),
              ),
            ),
            // Screen title anchored to the bottom of the expanded area —
            // scrolls out of view cleanly when the AppBar collapses.
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: ShaderMask(
                  shaderCallback: (bounds) =>
                      screenTitleGradient.createShader(bounds),
                  child: Text(
                    screenTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact brand mark: rounded logo tile with a soft aqua glow,
/// followed by the "Clique Pix" wordmark in the primary gradient.
/// Sized for the toolbar (28 px icon, 20 px text).
class _CliquePixWordmark extends StatelessWidget {
  const _CliquePixWordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.electricAqua.withValues(alpha: 0.35),
                blurRadius: 24,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/logo.png',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 18),
        Flexible(
          child: ShaderMask(
            shaderCallback: (bounds) =>
                AppGradients.primary.createShader(bounds),
            child: const Text(
              'Clique Pix',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 40,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
