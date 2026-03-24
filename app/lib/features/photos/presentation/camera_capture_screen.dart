import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/gradient_button.dart';
import 'photos_providers.dart';

class CameraCaptureScreen extends ConsumerStatefulWidget {
  final String eventId;
  const CameraCaptureScreen({super.key, required this.eventId});

  @override
  ConsumerState<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends ConsumerState<CameraCaptureScreen> {
  File? _selectedImage;
  bool _isUploading = false;
  String _statusText = '';
  double _progress = 0;

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 100);
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _upload() async {
    if (_selectedImage == null) return;

    setState(() { _isUploading = true; _progress = 0; _statusText = 'Compressing...'; });

    try {
      // Step 1: Compress
      final compression = ref.read(imageCompressionProvider);
      final compressed = await compression.compressImage(_selectedImage!);
      setState(() { _progress = 0.2; _statusText = 'Getting upload URL...'; });

      // Step 2: Get upload URL
      final repo = ref.read(photosRepositoryProvider);
      final uploadInfo = await repo.getUploadUrl(widget.eventId);
      setState(() { _progress = 0.4; _statusText = 'Uploading...'; });

      // Step 3: Upload to blob storage
      final blobUpload = ref.read(blobUploadProvider);
      await blobUpload.uploadToBlob(uploadInfo.uploadUrl, compressed.file);
      setState(() { _progress = 0.8; _statusText = 'Confirming...'; });

      // Step 4: Confirm upload
      await repo.confirmUpload(
        widget.eventId,
        photoId: uploadInfo.photoId,
        mimeType: 'image/jpeg',
        width: compressed.width,
        height: compressed.height,
        originalFilename: _selectedImage!.path.split('/').last,
      );
      setState(() { _progress = 1.0; _statusText = 'Done!'; });

      // Clean up temp file
      if (await compressed.file.exists()) {
        await compressed.file.delete();
      }

      // Refresh feed and go back
      ref.invalidate(eventPhotosProvider(widget.eventId));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() { _isUploading = false; _statusText = ''; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share Photo')),
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.standardPadding),
        child: Column(
          children: [
            Expanded(
              child: _selectedImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      child: Image.file(_selectedImage!, fit: BoxFit.contain),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, size: 80, color: AppColors.deepBlue.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        Text('Choose a photo to share', style: AppTextStyles.body.copyWith(color: AppColors.secondaryText)),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _SourceButton(
                              icon: Icons.camera_alt,
                              label: 'Camera',
                              onTap: _pickFromCamera,
                            ),
                            const SizedBox(width: 24),
                            _SourceButton(
                              icon: Icons.photo_library,
                              label: 'Gallery',
                              onTap: _pickFromGallery,
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            if (_isUploading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress, color: AppColors.deepBlue),
              const SizedBox(height: 8),
              Text(_statusText, style: AppTextStyles.caption),
            ],
            const SizedBox(height: 16),
            if (_selectedImage != null && !_isUploading)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _selectedImage = null),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      child: const Text('Change'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: GradientButton(text: 'Upload', onPressed: _upload),
                  ),
                ],
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.whiteSurface,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: AppColors.secondaryText.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppColors.deepBlue),
            const SizedBox(height: 8),
            Text(label, style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}
