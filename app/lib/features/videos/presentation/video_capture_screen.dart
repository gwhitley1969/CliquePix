import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'videos_providers.dart';

/// Pick or record a video, validate it, then navigate to the upload screen.
/// Mirrors the photo capture flow but skips editing entirely (videos in v1
/// are upload-and-share, no in-app modification).
class VideoCaptureScreen extends ConsumerStatefulWidget {
  final String eventId;
  const VideoCaptureScreen({super.key, required this.eventId});

  @override
  ConsumerState<VideoCaptureScreen> createState() => _VideoCaptureScreenState();
}

class _VideoCaptureScreenState extends ConsumerState<VideoCaptureScreen> {
  bool _isValidating = false;
  String? _errorText;

  Future<void> _pickVideo(ImageSource source) async {
    setState(() {
      _isValidating = false;
      _errorText = null;
    });

    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked == null || !mounted) return;

    setState(() => _isValidating = true);

    final file = File(picked.path);
    final validator = ref.read(videoValidationServiceProvider);
    final result = await validator.validate(file);

    if (!mounted) return;

    if (!result.isValid) {
      setState(() {
        _isValidating = false;
        _errorText = result.errorMessage;
      });
      return;
    }

    // Navigate to upload screen with the validated file
    context.pushReplacement(
      '/events/${widget.eventId}/videos/upload',
      extra: {
        'file': file,
        'durationSeconds': result.duration!.inSeconds,
        'width': result.width,
        'height': result.height,
        'fileSizeBytes': result.fileSizeBytes,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryText,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Add a video'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.standardPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isValidating) ...[
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.electricAqua),
              ),
              const SizedBox(height: 16),
              const Text(
                'Checking your video...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ] else ...[
              Icon(
                Icons.videocam_outlined,
                size: 96,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 24),
              const Text(
                'Share a video with your event',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Up to 5 minutes long. MP4 or MOV.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _pickVideo(ImageSource.camera),
                  icon: const Icon(Icons.videocam),
                  label: const Text('Record video'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.electricAqua,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _pickVideo(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from gallery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _errorText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
