import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme/app_colors.dart';

/// User avatar — renders a CachedNetworkImage inside a gradient-ring circle
/// when `imageUrl` (or `thumbUrl`) is present, otherwise falls back to
/// initials. The gradient is auto-hashed from the user's display name
/// unless `framePreset` (1..4) overrides it.
///
/// Size-aware URL selection: when `size < 64`, the 128px `thumbUrl` is
/// preferred because it renders sharp on cards without pulling the full
/// 512px original. For the profile hero (88pt) and anything larger, the
/// full `imageUrl` is used.
class AvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final String? thumbUrl;
  final String name;
  final double size;
  final bool showGradientRing;
  final int? framePreset;
  final String? cacheKey;

  const AvatarWidget({
    super.key,
    this.imageUrl,
    this.thumbUrl,
    required this.name,
    this.size = 40,
    this.showGradientRing = true,
    this.framePreset,
    this.cacheKey,
  });

  static const List<List<Color>> _palette = [
    [AppColors.electricAqua, AppColors.deepBlue],
    [AppColors.deepBlue, AppColors.violetAccent],
    [AppColors.violetAccent, Color(0xFFEC4899)],
    [AppColors.electricAqua, AppColors.violetAccent],
    [Color(0xFFEC4899), AppColors.electricAqua],
  ];

  /// Resolve a gradient pair from either an explicit preset (1..4 → palette
  /// indices 0..3) or the display-name hash. Preset 0 falls back to the
  /// hash-based gradient — treated as "auto-choose the default color".
  List<Color> _resolveGradient() {
    if (framePreset != null && framePreset! >= 1 && framePreset! <= 4) {
      return _palette[framePreset! - 1];
    }
    final hash = name.hashCode.abs() % _palette.length;
    return _palette[hash];
  }

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty
        ? name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join()
        : '?';
    final colors = _resolveGradient();
    final ringWidth = size * 0.06;

    // Prefer thumb for card-size avatars. 64px is the break — below this
    // the 128px thumb is 2x oversampled (fine for retina); above this we
    // want the full-res original.
    final preferThumb = size < 64 && thumbUrl != null && thumbUrl!.isNotEmpty;
    final effectiveUrl = preferThumb ? thumbUrl : imageUrl;
    final effectiveCacheKey = preferThumb && cacheKey != null
        ? '${cacheKey}_thumb'
        : cacheKey;

    Widget avatar;
    if (effectiveUrl != null && effectiveUrl.isNotEmpty) {
      avatar = CircleAvatar(
        radius: size / 2 - ringWidth - 1,
        backgroundImage: CachedNetworkImageProvider(
          effectiveUrl,
          cacheKey: effectiveCacheKey,
        ),
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
