import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../domain/blob_upload_service.dart';
import 'photos_providers.dart';

class CameraCaptureScreen extends ConsumerStatefulWidget {
  final String eventId;
  const CameraCaptureScreen({super.key, required this.eventId});

  @override
  ConsumerState<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends ConsumerState<CameraCaptureScreen> {
  File? _editedImage;
  bool _isUploading = false;
  String _statusText = '';
  String? _errorText;
  double _progress = 0;

  Future<void> _pickAndEdit(ImageSource source) async {
    debugPrint('[CliquePix] _pickAndEdit: source=$source');
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 100);
    if (picked == null || !mounted) return;
    debugPrint('[CliquePix] _pickAndEdit: picked=${picked.path}');

    // Capture edited file via closure — set by onImageEditingComplete,
    // read by onCloseEditor to update state after the editor pops.
    File? editedFile;

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProImageEditor.file(
            File(picked.path),
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (Uint8List bytes) async {
                debugPrint('[CliquePix] onImageEditingComplete: ${bytes.length} bytes');
                final dir = await getTemporaryDirectory();
                final file = File('${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg');
                await file.writeAsBytes(bytes);
                editedFile = file;
                // DON'T pop here — ProImageEditor v5.x calls onCloseEditor
                // immediately after this callback completes. Popping here
                // would double-pop and remove CameraCaptureScreen too.
              },
              onCloseEditor: () {
                debugPrint('[CliquePix] onCloseEditor: editedFile=${editedFile?.path}');
                if (mounted) {
                  Navigator.of(context).pop(); // Pop the editor only
                  if (editedFile != null) {
                    setState(() {
                      _editedImage = editedFile;
                      _errorText = null;
                    });
                  }
                }
              },
            ),
            configs: const ProImageEditorConfigs(),
          ),
        ),
      );
    }
  }

  Future<void> _upload() async {
    if (_editedImage == null) return;
    debugPrint('[CliquePix] _upload: starting, eventId=${widget.eventId}, file=${_editedImage!.path}');

    setState(() { _isUploading = true; _progress = 0; _statusText = 'Compressing...'; _errorText = null; });

    try {
      final compression = ref.read(imageCompressionProvider);
      final compressed = await compression.compressImage(_editedImage!);
      debugPrint('[CliquePix] _upload: compressed, size=${compressed.file.lengthSync()}, ${compressed.width}x${compressed.height}');
      setState(() { _progress = 0.2; _statusText = 'Getting upload URL...'; });

      final repo = ref.read(photosRepositoryProvider);
      final uploadInfo = await repo.getUploadUrl(widget.eventId);
      debugPrint('[CliquePix] _upload: got uploadUrl, photoId=${uploadInfo.photoId}');
      setState(() { _progress = 0.4; _statusText = 'Uploading to cloud...'; });

      final blobUpload = ref.read(blobUploadProvider);
      await blobUpload.uploadToBlob(uploadInfo.uploadUrl, compressed.file);
      debugPrint('[CliquePix] _upload: blob upload complete');
      setState(() { _progress = 0.8; _statusText = 'Confirming...'; });

      await repo.confirmUpload(
        widget.eventId,
        photoId: uploadInfo.photoId,
        mimeType: 'image/jpeg',
        width: compressed.width,
        height: compressed.height,
        originalFilename: _editedImage!.path.split('/').last,
      );
      debugPrint('[CliquePix] _upload: confirm complete');
      setState(() { _progress = 1.0; _statusText = 'Done!'; });

      try {
        if (await compressed.file.exists()) await compressed.file.delete();
        if (await _editedImage!.exists()) await _editedImage!.delete();
      } catch (_) {}

      ref.invalidate(eventPhotosProvider(widget.eventId));
      debugPrint('[CliquePix] _upload: feed invalidated, popping back');
      if (mounted) context.pop();
    } catch (e, stack) {
      debugPrint('[CliquePix] _upload: ERROR at "$_statusText": $e');
      debugPrint('[CliquePix] _upload: stack: $stack');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorText = _friendlyError(e, _statusText);
          _statusText = '';
        });
      }
    }
  }

  String _friendlyError(Object e, String stage) {
    if (e is BlobUploadFailure) {
      switch (e.azureCode) {
        case 'AuthorizationFailure':
        case 'AuthenticationFailed':
          return 'Upload permission expired. Tap retry.';
        case 'InvalidHeaderValue':
          return 'Upload rejected by storage. Please try again. (InvalidHeaderValue)';
        case 'RequestBodyTooLarge':
          return 'This photo is too large to upload.';
      }
      final code = e.azureCode ?? e.statusCode?.toString() ?? 'unknown';
      return 'Upload failed. Please try again. (code: $code)';
    }
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Network timed out. Check your connection and retry.';
      }
      final status = e.response?.statusCode;
      switch (status) {
        case 401:
          return "You've been signed out. Please sign in again.";
        case 403:
          return 'You can no longer post to this event.';
        case 404:
          return 'This event no longer exists. Go back and pick another.';
      }
      if (status != null && status >= 500) {
        return 'Something went wrong on our end. Please try again.';
      }
    }
    return kDebugMode
        ? 'Upload failed at: $stage\n$e'
        : 'Upload failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1525),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1525),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/events');
            }
          },
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
          child: const Text('Share Photo', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        centerTitle: true,
      ),
      body: _isUploading
          ? _buildUploadProgress()
          : _editedImage != null
              ? _buildPreview()
              : _buildPicker(),
    );
  }

  Widget _buildPicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.electricAqua.withValues(alpha: 0.2), blurRadius: 30, spreadRadius: 5),
                ],
              ),
              child: ShaderMask(
                shaderCallback: (bounds) => AppGradients.primary.createShader(bounds),
                child: const Icon(Icons.add_a_photo_rounded, size: 72, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Choose a photo to edit & share',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SourceButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  colors: [AppColors.electricAqua, AppColors.deepBlue],
                  onTap: () => _pickAndEdit(ImageSource.camera),
                ),
                const SizedBox(width: 20),
                _SourceButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  colors: [AppColors.deepBlue, AppColors.violetAccent],
                  onTap: () => _pickAndEdit(ImageSource.gallery),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(_editedImage!, fit: BoxFit.contain),
            ),
          ),
        ),

        // Error message
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(_errorText!, style: const TextStyle(color: AppColors.error, fontSize: 13), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _upload,
                    child: const Text('Tap to Retry', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700, fontSize: 14, decoration: TextDecoration.underline)),
                  ),
                ],
              ),
            ),
          ),

        // Upload button — BIG and unmissable
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.deepBlue.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _upload,
                borderRadius: BorderRadius.circular(16),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Upload to Event',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Change photo link
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: GestureDetector(
            onTap: () => setState(() { _editedImage = null; _errorText = null; }),
            child: Text(
              'Change Photo',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14, decoration: TextDecoration.underline, decorationColor: Colors.white.withValues(alpha: 0.3)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadProgress() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: _progress > 0 ? _progress : null,
                color: AppColors.electricAqua,
                strokeWidth: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _statusText,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).round()}%',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;

  const _SourceButton({required this.icon, required this.label, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [colors[0].withValues(alpha: 0.1), colors[1].withValues(alpha: 0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: colors[0].withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: colors[0]),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
