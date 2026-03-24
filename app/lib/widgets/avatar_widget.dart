import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class AvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;

  const AvatarWidget({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty
        ? name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join()
        : '?';

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(imageUrl!),
        backgroundColor: AppColors.softAquaBackground,
      );
    }

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.deepBlue.withOpacity(0.1),
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.deepBlue,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.35,
        ),
      ),
    );
  }
}
