import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme/app_colors.dart';

class AvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final bool showGradientRing;

  const AvatarWidget({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 40,
    this.showGradientRing = true,
  });

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
    final initials = name.isNotEmpty
        ? name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join()
        : '?';
    final colors = _gradientForName(name);
    final ringWidth = size * 0.06;

    Widget avatar;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      avatar = CircleAvatar(
        radius: size / 2 - ringWidth - 1,
        backgroundImage: CachedNetworkImageProvider(imageUrl!),
        backgroundColor: AppColors.softAquaBackground,
      );
    } else {
      avatar = CircleAvatar(
        radius: size / 2 - ringWidth - 1,
        backgroundColor: const Color(0xFF1A1F35),
        child: Text(
          initials,
          style: TextStyle(
            color: colors[0],
            fontWeight: FontWeight.w700,
            fontSize: size * 0.32,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    if (!showGradientRing) return avatar;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.all(ringWidth),
      child: avatar,
    );
  }
}
