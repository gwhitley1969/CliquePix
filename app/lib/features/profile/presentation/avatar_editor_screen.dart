import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/user_model.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/avatar_repository.dart';
import 'avatar_providers.dart';

/// Full-screen square-crop editor with filter + frame selection + save.
/// Receives a raw picked file (post-picker-sheet), runs `image_cropper`
/// inline, then shows a live preview with selectable filter/frame rows
/// before upload.
class AvatarEditorScreen extends ConsumerStatefulWidget {
  final File sourceFile;
  const AvatarEditorScreen({super.key, required this.sourceFile});

  @override
  ConsumerState<AvatarEditorScreen> createState() => _AvatarEditorScreenState();
}

class _AvatarEditorScreenState extends ConsumerState<AvatarEditorScreen> {
  File? _croppedFile;
  AvatarFilter _filter = AvatarFilter.original;
  int _framePreset = 0;
  bool _uploading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Seed frame preset from current user so the user sees their existing
    // frame choice instead of a silent reset to preset 0.
    final auth = ref.read(authStateProvider);
    if (auth is AuthAuthenticated) {
      _framePreset = auth.user.avatarFramePreset;
    }
    // Fire the crop immediately on mount — no extra tap needed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCrop());
  }

  Future<void> _runCrop() async {
    final repo = ref.read(avatarRepositoryProvider);
    final cropped = await repo.crop(widget.sourceFile.path);
    if (!mounted) return;
    if (cropped == null) {
      // User bailed from the cropper. Pop back so they can re-pick.
      Navigator.of(context).pop();
      return;
    }
    setState(() => _croppedFile = cropped);
  }

  Future<void> _save() async {
    if (_croppedFile == null) return;
    setState(() {
      _uploading = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();
    final repo = ref.read(avatarRepositoryProvider);
    try {
      final prepared = await repo.prepareForUpload(_croppedFile!, _filter);
      UserModel updated = await repo.uploadPrepared(prepared);
      // Apply the chosen frame preset if it changed from the caller's
      // baseline. Done as a separate PATCH so the upload payload stays
      // purely media-related.
      if (updated.avatarFramePreset != _framePreset) {
        updated = await repo.updateFrame(_framePreset);
      }
      ref.read(authStateProvider.notifier).updateUserAvatar(updated);
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('AuthorizationFailure') || s.contains('AuthenticationFailed')) {
      return 'Upload permission expired. Tap Save to retry.';
    }
    if (s.contains('SocketException') || s.contains('TimeoutException')) {
      return 'Network timed out. Check your connection and retry.';
    }
    return 'Upload failed. Tap Save to retry.';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final displayName = auth is AuthAuthenticated ? auth.user.displayName : '';
    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Your Avatar'),
        actions: [
          if (_croppedFile != null && !_uploading)
            TextButton(
              onPressed: _save,
              child: const Text(
                'Save',
                style: TextStyle(
                  color: AppColors.electricAqua,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          if (_uploading)
            const Padding(
              padding: EdgeInsets.only(right: 16, top: 14, bottom: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(AppColors.electricAqua),
                ),
              ),
            ),
        ],
      ),
      body: _croppedFile == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.electricAqua))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Live preview inside a gradient-ring circle so the user
                  // sees exactly how it'll look on every card in the app.
                  Center(child: _buildPreview(displayName)),
                  const SizedBox(height: 32),
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _SectionLabel('Filter'),
                  const SizedBox(height: 10),
                  _FilterRow(
                    selected: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: 28),
                  _SectionLabel('Frame color'),
                  const SizedBox(height: 10),
                  _FrameRow(
                    selected: _framePreset,
                    onChanged: (p) => setState(() => _framePreset = p),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildPreview(String name) {
    // Apply a preview-only ColorFilter so the user sees the filter
    // without having to bake it first. Final upload re-bakes via
    // prepareForUpload so the cloud copy matches what they saw.
    final previewMatrix = _previewMatrix(_filter);
    return Container(
      width: 176,
      height: 176,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: _frameColors(_framePreset, name),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: ClipOval(
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(previewMatrix),
          child: Image.file(_croppedFile!, fit: BoxFit.cover),
        ),
      ),
    );
  }

  List<double> _previewMatrix(AvatarFilter f) {
    // Share the same matrices the repository uses at bake time.
    switch (f) {
      case AvatarFilter.original:
        return const [
          1, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 1, 0, 0,
          0, 0, 0, 1, 0,
        ];
      case AvatarFilter.blackAndWhite:
        return const [
          0.299, 0.587, 0.114, 0, 0,
          0.299, 0.587, 0.114, 0, 0,
          0.299, 0.587, 0.114, 0, 0,
          0,     0,     0,     1, 0,
        ];
      case AvatarFilter.warm:
        return const [
          1.10, 0,    0,    0, 5,
          0,    1.05, 0,    0, 0,
          0,    0,    0.90, 0, 0,
          0,    0,    0,    1, 0,
        ];
      case AvatarFilter.cool:
        return const [
          0.90, 0,    0,    0, 0,
          0,    1.02, 0,    0, 0,
          0,    0,    1.10, 0, 5,
          0,    0,    0,    1, 0,
        ];
    }
  }

  List<Color> _frameColors(int preset, String name) {
    // Mirror AvatarWidget._palette / _resolveGradient so the preview
    // matches the final render 1:1.
    const palette = [
      [AppColors.electricAqua, AppColors.deepBlue],
      [AppColors.deepBlue, AppColors.violetAccent],
      [AppColors.violetAccent, Color(0xFFEC4899)],
      [AppColors.electricAqua, AppColors.violetAccent],
      [Color(0xFFEC4899), AppColors.electricAqua],
    ];
    if (preset >= 1 && preset <= 4) return palette[preset - 1];
    final hash = name.hashCode.abs() % palette.length;
    return palette[hash];
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final AvatarFilter selected;
  final ValueChanged<AvatarFilter> onChanged;

  const _FilterRow({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const filters = AvatarFilter.values;
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final f = filters[i];
          final isSelected = f == selected;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(f);
            },
            child: Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.electricAqua
                          : Colors.white.withValues(alpha: 0.15),
                      width: isSelected ? 2.5 : 1,
                    ),
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  child: Icon(
                    _iconFor(f),
                    color: isSelected ? AppColors.electricAqua : Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _labelFor(f),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(AvatarFilter f) {
    switch (f) {
      case AvatarFilter.original: return Icons.image_outlined;
      case AvatarFilter.blackAndWhite: return Icons.tonality_rounded;
      case AvatarFilter.warm: return Icons.wb_sunny_rounded;
      case AvatarFilter.cool: return Icons.ac_unit_rounded;
    }
  }

  String _labelFor(AvatarFilter f) {
    switch (f) {
      case AvatarFilter.original: return 'Original';
      case AvatarFilter.blackAndWhite: return 'B & W';
      case AvatarFilter.warm: return 'Warm';
      case AvatarFilter.cool: return 'Cool';
    }
  }
}

class _FrameRow extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _FrameRow({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // 0 = auto-gradient (hash), 1..4 = explicit palette positions.
    const gradients = [
      // preset 0 = auto; we render it with a neutral swatch label
      [AppColors.electricAqua, AppColors.deepBlue], // preset 1
      [AppColors.deepBlue, AppColors.violetAccent], // preset 2
      [AppColors.violetAccent, Color(0xFFEC4899)],  // preset 3
      [AppColors.electricAqua, AppColors.violetAccent], // preset 4
    ];
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 5, // auto + 4 presets
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final isSelected = i == selected;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.2),
                  width: isSelected ? 3 : 1,
                ),
                gradient: i == 0
                    ? null
                    : LinearGradient(
                        colors: gradients[i - 1],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: i == 0 ? Colors.white.withValues(alpha: 0.08) : null,
              ),
              child: i == 0
                  ? const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white70)
                  : null,
            ),
          );
        },
      ),
    );
  }
}
