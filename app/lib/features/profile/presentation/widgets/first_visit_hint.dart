import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_colors.dart';

/// Dismissible pill shown above the empty-state avatar the first time a
/// user opens Profile. Points them at the tappable gradient ring. Gated
/// on a one-shot SharedPreferences flag so it never reappears.
class FirstVisitHint extends StatefulWidget {
  final String prefsKey;
  final String text;

  const FirstVisitHint({
    super.key,
    this.prefsKey = 'avatar_hint_dismissed',
    this.text = 'Tap to add your photo ✨',
  });

  @override
  State<FirstVisitHint> createState() => _FirstVisitHintState();
}

class _FirstVisitHintState extends State<FirstVisitHint> {
  bool? _shouldShow; // tri-state: null = loading, true = show, false = hide

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _shouldShow = !(prefs.getBool(widget.prefsKey) ?? false);
    });
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(widget.prefsKey, true);
    if (!mounted) return;
    setState(() => _shouldShow = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldShow != true) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _dismiss,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: AppColors.electricAqua.withValues(alpha: 0.14),
          border: Border.all(color: AppColors.electricAqua.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: const TextStyle(
                color: AppColors.electricAqua,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.close_rounded,
              size: 14,
              color: AppColors.electricAqua.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
