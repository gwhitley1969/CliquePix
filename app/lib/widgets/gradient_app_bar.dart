import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_gradients.dart';

class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  const GradientAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.primary),
      child: AppBar(
        title: Text(title, style: const TextStyle(color: AppColors.whiteSurface, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.whiteSurface,
        elevation: 0,
        actions: actions,
        leading: leading,
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
