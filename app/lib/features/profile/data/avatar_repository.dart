import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../models/user_model.dart';
import '../../photos/domain/blob_upload_service.dart';
import 'avatar_api.dart';

/// Avatar-specific compression knobs. Distinct from photo upload's
/// AppConstants.maxImageDimension (2048) because avatars are always
/// square and much smaller. 512px covers the 88pt profile hero at 2x
/// retina with headroom. JPEG quality 85 (vs photos' 80) because faces
/// matter more than general scenery.
const int _avatarMaxDim = 512;
const int _avatarJpegQuality = 85;

/// Filter presets offered during the crop step. Each preset maps to a
/// 5x4 ColorFilter matrix applied to the RGB channels; `null` = no-op
/// (Original). Matrices stay pure (no fancy LUTs) so no native deps are
/// needed — `Canvas.drawImage` + `Paint..colorFilter` bakes the filter
/// into a new `ui.Image` we then encode to JPEG.
enum AvatarFilter {
  original,
  blackAndWhite,
  warm,
  cool,
}

/// Orchestrator for the full avatar upload flow: pick → crop → filter →
/// compress → SAS → blob PUT → confirm. Returns the refreshed
/// `UserModel` so callers can update `authStateProvider` in one atomic
/// step.
class AvatarRepository {
  final AvatarApi _api;
  final BlobUploadService _blobUpload;
  final ImagePicker _picker;

  AvatarRepository(this._api, this._blobUpload) : _picker = ImagePicker();

  /// Prompt the user to pick a source (camera or gallery) and return the
  /// raw XFile. Null = user cancelled.
  Future<XFile?> pickFromGallery() => _picker.pickImage(source: ImageSource.gallery);
  Future<XFile?> pickFromCamera() => _picker.pickImage(source: ImageSource.camera);

  /// Run the native square cropper. Returns the cropped file or null if
  /// the user cancelled. `image_cropper` 9.x returns a `CroppedFile`.
  Future<File?> crop(String sourcePath) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 100, // keep lossless here; final compression happens after filtering
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop avatar',
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop avatar',
          aspectRatioLockEnabled: true,
          aspectRatioPickerButtonHidden: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null) return null;
    return File(cropped.path);
  }

  /// Apply an optional color filter to the cropped image and re-encode
  /// as a compressed JPEG at 512x512 q85.
  Future<File> prepareForUpload(File croppedFile, AvatarFilter filter) async {
    final bytes = await croppedFile.readAsBytes();
    final filtered = filter == AvatarFilter.original
        ? bytes
        : await _bakeFilter(bytes, filter);

    // Final compression pass. flutter_image_compress handles the resize
    // to 512x512 and strips EXIF (keepExif: false).
    final tempDir = await getTemporaryDirectory();
    final out = '${tempDir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressWithList(
      filtered,
      minWidth: _avatarMaxDim,
      minHeight: _avatarMaxDim,
      quality: _avatarJpegQuality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    final file = File(out);
    await file.writeAsBytes(result);
    return file;
  }

  /// End-to-end: get SAS → PUT bytes → confirm. Returns the refreshed
  /// user. Caller is responsible for updating `authStateProvider`.
  Future<UserModel> uploadPrepared(File preparedJpeg) async {
    final sas = await _api.getUploadUrl();
    await _blobUpload.uploadToBlob(sas.uploadUrl, preparedJpeg);
    return _api.confirm();
  }

  Future<UserModel> deleteAvatar() => _api.delete();

  Future<UserModel> updateFrame(int preset) => _api.updateFrame(preset);

  Future<UserModel> snoozePrompt() => _api.setPromptAction('snooze');
  Future<UserModel> dismissPrompt() => _api.setPromptAction('dismiss');

  // ─── Filter baking (Flutter core, no extra deps) ──────────────────────────

  /// Bake a color-matrix filter into the image bytes. Uses
  /// `Canvas.drawImage` with a `ColorFilter.matrix`, then encodes the
  /// result back to PNG (lossless pre-compression step) and hands it to
  /// `flutter_image_compress` for final JPEG encoding.
  Future<Uint8List> _bakeFilter(Uint8List sourceBytes, AvatarFilter filter) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(sourceBytes, completer.complete);
    final src = await completer.future;

    final matrix = _matrixFor(filter);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..colorFilter = ColorFilter.matrix(matrix);
    canvas.drawImage(src, Offset.zero, paint);
    final picture = recorder.endRecording();
    final out = await picture.toImage(src.width, src.height);
    final byteData = await out.toByteData(format: ui.ImageByteFormat.png);
    src.dispose();
    out.dispose();
    return byteData!.buffer.asUint8List();
  }

  List<double> _matrixFor(AvatarFilter f) {
    switch (f) {
      case AvatarFilter.original:
        return const [
          1, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 1, 0, 0,
          0, 0, 0, 1, 0,
        ];
      case AvatarFilter.blackAndWhite:
        // Luminance-weighted desaturation (BT.601 coefficients).
        return const [
          0.299, 0.587, 0.114, 0, 0,
          0.299, 0.587, 0.114, 0, 0,
          0.299, 0.587, 0.114, 0, 0,
          0,     0,     0,     1, 0,
        ];
      case AvatarFilter.warm:
        // Pushes reds/yellows, dims blues. Subtle — this is a face-tune
        // preset, not Instagram Valencia.
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
}
