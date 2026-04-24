import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../models/user_model.dart';

/// Thin Dio wrapper over the five avatar endpoints. Stateless; the
/// real upload pipeline (pick → crop → compress → PUT → confirm) lives
/// in `AvatarRepository`.
class AvatarApi {
  final Dio _dio;

  AvatarApi(this._dio);

  /// Request a 5-minute write+create User Delegation SAS for the user's
  /// avatar blob. Returns `{upload_url, blob_path}`. Client PUTs the
  /// compressed JPEG to `upload_url`, then calls `confirm()`.
  Future<({String uploadUrl, String blobPath})> getUploadUrl() async {
    final resp = await _dio.post(ApiEndpoints.avatarUploadUrl);
    final data = resp.data['data'] as Map<String, dynamic>;
    return (
      uploadUrl: data['upload_url'] as String,
      blobPath: data['blob_path'] as String,
    );
  }

  /// Notify the backend that the upload completed. Backend verifies the
  /// blob, generates the 128px thumbnail, updates the users row, and
  /// returns the full enriched user (with new avatar_url/thumb_url/etc.).
  Future<UserModel> confirm() async {
    final resp = await _dio.post(ApiEndpoints.avatarConfirm);
    return UserModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  /// Remove the user's avatar. Deletes both blobs, nulls the DB columns,
  /// and returns the updated user (now `avatar_url: null`, initials
  /// fallback will re-activate on screens watching `authStateProvider`).
  Future<UserModel> delete() async {
    final resp = await _dio.delete(ApiEndpoints.avatarDelete);
    return UserModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  /// Change the gradient frame preset (0..4). Works whether or not a
  /// custom avatar is uploaded.
  Future<UserModel> updateFrame(int preset) async {
    final resp = await _dio.patch(
      ApiEndpoints.avatarFrame,
      data: {'frame_preset': preset},
    );
    return UserModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  /// Record the user's response to the first-sign-in welcome prompt.
  /// `dismiss` = "No Thanks" (never re-prompt). `snooze` = "Maybe Later"
  /// (re-prompt in 7 days). "Yes" needs no call — uploading suppresses
  /// future prompts automatically.
  Future<UserModel> setPromptAction(String action) async {
    final resp = await _dio.post(
      ApiEndpoints.avatarPrompt,
      data: {'action': action},
    );
    return UserModel.fromJson(resp.data['data'] as Map<String, dynamic>);
  }
}
