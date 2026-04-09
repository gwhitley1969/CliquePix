import 'package:uuid/uuid.dart';

enum UploadStage { localOnly, uploading, committing, processing, failed, complete }

class LocalPendingVideo {
  final String localTempId;
  final String eventId;
  final String localFilePath;
  final int durationSeconds;
  final int? width;
  final int? height;
  final int? fileSizeBytes;
  final DateTime createdAt;
  final UploadStage uploadStage;
  final double uploadProgress;
  final String? serverVideoId;
  final String? previewUrl;
  final String? errorMessage;

  const LocalPendingVideo({
    required this.localTempId,
    required this.eventId,
    required this.localFilePath,
    required this.durationSeconds,
    this.width,
    this.height,
    this.fileSizeBytes,
    required this.createdAt,
    this.uploadStage = UploadStage.localOnly,
    this.uploadProgress = 0.0,
    this.serverVideoId,
    this.previewUrl,
    this.errorMessage,
  });

  LocalPendingVideo copyWith({
    UploadStage? uploadStage,
    double? uploadProgress,
    String? serverVideoId,
    String? previewUrl,
    String? errorMessage,
  }) {
    return LocalPendingVideo(
      localTempId: localTempId,
      eventId: eventId,
      localFilePath: localFilePath,
      durationSeconds: durationSeconds,
      width: width,
      height: height,
      fileSizeBytes: fileSizeBytes,
      createdAt: createdAt,
      uploadStage: uploadStage ?? this.uploadStage,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      serverVideoId: serverVideoId ?? this.serverVideoId,
      previewUrl: previewUrl ?? this.previewUrl,
      errorMessage: errorMessage,
    );
  }

  String get durationLabel {
    final minutes = durationSeconds ~/ 60;
    final remaining = durationSeconds % 60;
    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }

  static String generateId() => const Uuid().v4();
}
