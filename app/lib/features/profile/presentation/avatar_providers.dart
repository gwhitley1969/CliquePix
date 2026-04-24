import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_client.dart';
import '../../photos/domain/blob_upload_service.dart';
import '../../photos/presentation/photos_providers.dart';
import '../data/avatar_api.dart';
import '../data/avatar_repository.dart';

final avatarApiProvider = Provider<AvatarApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AvatarApi(apiClient.dio);
});

final avatarRepositoryProvider = Provider<AvatarRepository>((ref) {
  final api = ref.watch(avatarApiProvider);
  // Reuse the photo-side blob uploader — same Dio-based PUT pattern
  // covers avatar uploads without maintaining two implementations.
  final BlobUploadService blobUpload = ref.watch(blobUploadProvider);
  return AvatarRepository(api, blobUpload);
});
