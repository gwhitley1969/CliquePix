import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, Uint8List;
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
  String? _errorDetails;
  bool _showDetails = false;
  double _progress = 0;
  // 429 cooldown: wall-clock time at which retries become tappable again.
  DateTime? _retryAvailableAt;
  Timer? _cooldownTicker;
  Duration _cooldownRemaining = Duration.zero;

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    super.dispose();
  }

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

    setState(() {
      _isUploading = true;
      _progress = 0;
      _statusText = 'Compressing...';
      _errorText = null;
      _errorDetails = null;
      _showDetails = false;
    });

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

      // Best-effort temp-file cleanup. Don't let cleanup failures mask success.
      try {
        if (await compressed.file.exists()) await compressed.file.delete();
        if (await _editedImage!.exists()) await _editedImage!.delete();
      } catch (cleanupErr) {
        debugPrint('[CliquePix] _upload: temp cleanup failed (non-fatal): $cleanupErr');
      }

      ref.invalidate(eventPhotosProvider(widget.eventId));
      debugPrint('[CliquePix] _upload: feed invalidated, popping back');
      if (mounted) context.pop();
    } catch (e, stack) {
      debugPrint('[CliquePix] _upload: ERROR at "$_statusText": $e');
      debugPrint('[CliquePix] _upload: stack: $stack');
      if (mounted) {
        final friendly = _friendlyError(e, _statusText);
        final details = _diagnosticDetails(e, _statusText);
        final retryAfter = _extractRetryAfter(e);
        setState(() {
          _isUploading = false;
          _errorText = friendly;
          _errorDetails = details;
          _statusText = '';
        });
        if (retryAfter != null) {
          _startCooldown(retryAfter);
        }
      }
    }
  }

  /// Pulls the Retry-After hint from a 429 response. APIM emits both an
  /// HTTP `Retry-After` header (seconds) and a body like
  /// `{"statusCode":429,"message":"Rate limit is exceeded. Try again in 37 seconds."}`.
  /// We trust the header first, then fall back to parsing the body so we
  /// always have a number to count down from.
  Duration? _extractRetryAfter(Object e) {
    if (e is! DioException) return null;
    if (e.response?.statusCode != 429) return null;
    final headers = e.response?.headers;
    final headerVal = headers?.value('retry-after');
    if (headerVal != null) {
      final n = int.tryParse(headerVal.trim());
      if (n != null && n > 0) return Duration(seconds: n);
    }
    final body = e.response?.data;
    if (body is Map) {
      final msg = body['message']?.toString() ?? '';
      final m = RegExp(r'(\d+)\s*second').firstMatch(msg);
      if (m != null) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && n > 0) return Duration(seconds: n);
      }
    }
    return const Duration(seconds: 60);
  }

  void _startCooldown(Duration duration) {
    _cooldownTicker?.cancel();
    final until = DateTime.now().add(duration);
    setState(() {
      _retryAvailableAt = until;
      _cooldownRemaining = duration;
    });
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final remaining = until.difference(DateTime.now());
      if (remaining.isNegative || remaining.inSeconds <= 0) {
        t.cancel();
        setState(() {
          _retryAvailableAt = null;
          _cooldownRemaining = Duration.zero;
        });
      } else {
        setState(() => _cooldownRemaining = remaining);
      }
    });
  }

  bool get _retryDisabled =>
      _retryAvailableAt != null && DateTime.now().isBefore(_retryAvailableAt!);

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
      return 'Upload failed at "$stage". (code: $code)';
    }
    if (e is DioException) {
      // Check for a structured backend error code first — matches the
      // pattern used in video_upload_screen._friendlyError.
      final backendCode = _extractBackendErrorCode(e);
      if (backendCode != null) {
        switch (backendCode) {
          case 'EVENT_EXPIRED':
            return 'This event has ended. Photos can no longer be uploaded.';
          case 'NOT_MEMBER':
            return "You're no longer a member of this event's clique.";
          case 'EVENT_NOT_FOUND':
            return 'This event no longer exists. Go back and pick another.';
        }
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Network timed out. Check your connection and retry.';
        case DioExceptionType.connectionError:
          return "Can't reach the server. Check your connection and retry.";
        case DioExceptionType.cancel:
          return 'Upload cancelled.';
        case DioExceptionType.badCertificate:
          return 'Secure connection failed. Check your device clock and retry.';
        case DioExceptionType.unknown:
        case DioExceptionType.badResponse:
          break;
      }
      final status = e.response?.statusCode;
      switch (status) {
        case 401:
          return "You've been signed out. Please sign in again.";
        case 403:
          return 'You can no longer post to this event.';
        case 404:
          return 'This event no longer exists. Go back and pick another.';
        case 429:
          final retry = _extractRetryAfter(e);
          final secs = retry?.inSeconds ?? 60;
          return 'Too many requests. Please wait ${secs}s and retry.';
      }
      if (status != null && status >= 500) {
        return 'Server error at "$stage" (HTTP $status). Please try again.';
      }
      if (status != null) {
        return 'Upload failed at "$stage" (HTTP $status). Tap details for more.';
      }
      return 'Upload failed at "$stage" (no response). Tap details for more.';
    }
    final typeName = e.runtimeType.toString();
    return 'Upload failed at "$stage" ($typeName). Tap details for more.';
  }

  /// Extract a structured backend error code from a Dio response body.
  /// Backends return `{ "data": null, "error": { "code": "...", "message": "..." } }`.
  String? _extractBackendErrorCode(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final err = data['error'];
      if (err is Map<String, dynamic>) {
        final code = err['code'];
        if (code is String) return code;
      }
    }
    return null;
  }

  /// Verbose diagnostic blob shown in the expandable "Show details" section.
  /// Captures everything we'd want from an adb logcat session: stage, exception
  /// type, message, and (for Dio) response status + first chunk of the body.
  String _diagnosticDetails(Object e, String stage) {
    final buf = StringBuffer();
    buf.writeln('Stage: $stage');
    buf.writeln('Type: ${e.runtimeType}');
    if (e is DioException) {
      buf.writeln('Dio type: ${e.type.name}');
      buf.writeln('HTTP status: ${e.response?.statusCode ?? "(no response)"}');
      if (e.message != null) buf.writeln('Message: ${e.message}');
      if (e.error != null && e.error.toString().isNotEmpty) {
        buf.writeln('Cause: ${_truncate(e.error.toString(), 200)}');
      }
      final body = e.response?.data;
      if (body != null) {
        buf.writeln('Body: ${_truncate(body.toString(), 300)}');
      }
    } else if (e is BlobUploadFailure) {
      buf.writeln('HTTP status: ${e.statusCode ?? "(none)"}');
      buf.writeln('Azure code: ${e.azureCode ?? "(none)"}');
      buf.writeln('Azure message: ${e.azureMessage ?? "(none)"}');
      buf.writeln('Cause: ${_truncate(e.cause.toString(), 200)}');
    } else {
      buf.writeln('Message: ${_truncate(e.toString(), 300)}');
    }
    return buf.toString().trimRight();
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_errorText!, style: const TextStyle(color: AppColors.error, fontSize: 13), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: _retryDisabled ? null : _upload,
                        child: Text(
                          _retryDisabled
                              ? 'Wait ${_cooldownRemaining.inSeconds}s'
                              : 'Tap to Retry',
                          style: TextStyle(
                            color: _retryDisabled
                                ? AppColors.error.withValues(alpha: 0.5)
                                : AppColors.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            decoration: _retryDisabled ? null : TextDecoration.underline,
                          ),
                        ),
                      ),
                      if (_errorDetails != null)
                        GestureDetector(
                          onTap: () => setState(() => _showDetails = !_showDetails),
                          child: Text(
                            _showDetails ? 'Hide details' : 'Show details',
                            style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline),
                          ),
                        ),
                    ],
                  ),
                  if (_showDetails && _errorDetails != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _errorDetails!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          height: 1.4,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Upload button — BIG and unmissable
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Opacity(
            opacity: _retryDisabled ? 0.5 : 1.0,
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
                onTap: _retryDisabled ? null : _upload,
                borderRadius: BorderRadius.circular(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      _retryDisabled
                          ? 'Wait ${_cooldownRemaining.inSeconds}s'
                          : 'Upload to Event',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ],
                ),
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
