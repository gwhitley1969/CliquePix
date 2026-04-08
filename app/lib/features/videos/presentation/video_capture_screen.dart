import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'videos_providers.dart';

/// Pick or record a video, validate it, then let the user CONFIRM before
/// starting the upload. Mirrors the photo capture flow pattern where the
/// user sees the picked/edited media first and explicitly taps "Upload".
class VideoCaptureScreen extends ConsumerStatefulWidget {
  final String eventId;
  const VideoCaptureScreen({super.key, required this.eventId});

  @override
  ConsumerState<VideoCaptureScreen> createState() => _VideoCaptureScreenState();
}

class _VideoCaptureScreenState extends ConsumerState<VideoCaptureScreen> {
  bool _isValidating = false;
  String? _errorText;

  // Picked + validated video metadata (non-null once ready to upload)
  File? _pickedFile;
  int? _durationSeconds;
  int? _width;
  int? _height;
  int? _fileSizeBytes;

  Future<void> _pickVideo(ImageSource source) async {
    setState(() {
      _isValidating = false;
      _errorText = null;
      _pickedFile = null;
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

    // Store the validated video — user will tap "Upload" to confirm
    setState(() {
      _isValidating = false;
      _pickedFile = file;
      _durationSeconds = result.duration!.inSeconds;
      _width = result.width;
      _height = result.height;
      _fileSizeBytes = result.fileSizeBytes;
    });
  }

  void _startUpload() {
    if (_pickedFile == null || _durationSeconds == null) return;
    context.pushReplacement(
      '/events/${widget.eventId}/videos/upload',
      extra: {
        'file': _pickedFile!,
        'durationSeconds': _durationSeconds!,
        'width': _width,
        'height': _height,
        'fileSizeBytes': _fileSizeBytes,
      },
    );
  }

  void _discard() {
    setState(() {
      _pickedFile = null;
      _durationSeconds = null;
      _width = null;
      _height = null;
      _fileSizeBytes = null;
      _errorText = null;
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '$minutes:${remaining.toString().padLeft(2, '0')}';
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
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // State 1: validating (brief spinner while we probe the file)
    if (_isValidating) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.electricAqua),
          ),
          SizedBox(height: 16),
          Text(
            'Checking your video...',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      );
    }

    // State 2: video is picked and validated — show confirmation with Upload button
    if (_pickedFile != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Video info card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.electricAqua.withValues(alpha: 0.15),
                    border: Border.all(color: AppColors.electricAqua, width: 2),
                  ),
                  child: const Icon(Icons.videocam, size: 36, color: AppColors.electricAqua),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ready to upload',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.schedule, size: 14, color: Colors.white.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(_durationSeconds!),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.storage, size: 14, color: Colors.white.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text(
                      _formatFileSize(_fileSizeBytes ?? 0),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                    if (_width != null && _height != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.aspect_ratio, size: 14, color: Colors.white.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Text(
                        '${_width}×$_height',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Upload button (primary action)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startUpload,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Upload video'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.electricAqua,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Discard + pick different
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _discard,
              icon: const Icon(Icons.close),
              label: const Text('Choose a different video'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white30),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      );
    }

    // State 3: initial / error — show pick buttons
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.videocam_outlined,
          size: 96,
          color: Colors.white.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 24),
        const Text(
          'Share a video with your event',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Up to 5 minutes long. MP4 or MOV.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
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
    );
  }
}
