# Code Review Fixes — Priority Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all Critical and High issues found in the CliquePix v1 code review, then Medium issues.

**Architecture:** Fixes are applied in priority order (Critical → High → Medium) with related fixes grouped by file to minimize context-switching. Backend and Flutter fixes are interleaved by priority, not batched by layer.

**Tech Stack:** TypeScript/Node.js (Azure Functions backend), Dart/Flutter (mobile app)

---

## Task 1: Fix blob path prefix (C1) + thumbnail path (cascading)

**Files:**
- Modify: `backend/src/functions/photos.ts:85`

- [ ] **Step 1: Fix blob path construction**

In `photos.ts` line 85, change:
```typescript
const blobPath = `${event.circle_id}/${eventId}/${photoId}/original.jpg`;
```
to:
```typescript
const blobPath = `photos/${event.circle_id}/${eventId}/${photoId}/original.jpg`;
```

- [ ] **Step 2: Verify thumbnail path derivation still works**

Line 197 uses `photo.blob_path.replace('/original.jpg', '/thumb.jpg')` — this will now correctly produce `photos/{circleId}/{eventId}/{photoId}/thumb.jpg`. No change needed.

- [ ] **Step 3: Commit**

```bash
git add backend/src/functions/photos.ts
git commit -m "fix: add photos/ prefix to blob path per spec"
```

---

## Task 2: Fix confirmUpload — remove blob download, use blob properties, make thumbnail async (C2)

**Files:**
- Modify: `backend/src/functions/photos.ts:164-206`

- [ ] **Step 1: Remove sharp import and blob download from confirmUpload**

Replace lines 3, 164-206 in `photos.ts`. Remove `import sharp from 'sharp';` at line 3. Replace the sharp-based validation and inline thumbnail generation with blob-properties-based validation and async thumbnail trigger.

The new confirm section (after the `getBlobProperties` call at line 156) should be:

```typescript
    // Validate blob content type from actual blob properties
    const blobContentType = blobProps.contentType ?? '';
    if (!['image/jpeg', 'image/png'].includes(blobContentType)) {
      await deleteBlob(photo.blob_path);
      await execute('DELETE FROM photos WHERE id = $1', [photoId]);
      throw new ValidationError('File is not a valid JPEG or PNG image.');
    }

    // Use client-supplied dimensions (server does not download the blob)
    const finalWidth = width;
    const finalHeight = height;

    // Update photo record to active
    const updatedPhoto = await queryOne<Photo>(
      `UPDATE photos
       SET status = 'active',
           mime_type = $1,
           width = $2,
           height = $3,
           file_size_bytes = $4,
           original_filename = $5
       WHERE id = $6
       RETURNING *`,
      [mimeType, finalWidth, finalHeight, fileSizeBytes, originalFilename, photoId],
    );

    // Thumbnail generation happens asynchronously via blob-triggered function
    // For now, trigger it inline but non-blocking (non-fatal)
    generateThumbnailAsync(photo.blob_path, photoId).catch((err) => {
      console.error('Async thumbnail generation failed:', err);
    });
```

- [ ] **Step 2: Add async thumbnail helper at file level**

Add this function before the endpoint handlers:

```typescript
async function generateThumbnailAsync(blobPath: string, photoId: string): Promise<void> {
  const sharp = (await import('sharp')).default;
  const buffer = await downloadBlob(blobPath);
  const thumbBuffer = await sharp(buffer)
    .resize({ width: 400, height: 400, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 70 })
    .toBuffer();
  const thumbPath = blobPath.replace('/original.jpg', '/thumb.jpg');
  await uploadBlob(thumbPath, thumbBuffer, 'image/jpeg');
  await execute('UPDATE photos SET thumbnail_blob_path = $1 WHERE id = $2', [thumbPath, photoId]);
}
```

- [ ] **Step 3: Remove the static sharp import from line 3**

The dynamic import inside `generateThumbnailAsync` replaces it.

- [ ] **Step 4: Commit**

```bash
git add backend/src/functions/photos.ts
git commit -m "fix: remove blob download from confirmUpload, validate via blob properties, async thumbnail"
```

---

## Task 3: Fix SAS permissions and expiry (C3, C4)

**Files:**
- Modify: `backend/src/shared/services/sasService.ts:35,64`

- [ ] **Step 1: Remove create permission from upload SAS**

In `sasService.ts`, delete line 35:
```typescript
  permissions.create = true;
```

- [ ] **Step 2: Fix view SAS expiry from 15 minutes to 5 minutes**

In `sasService.ts` line 64, change:
```typescript
  const expiresOn = new Date(now.getTime() + 15 * 60 * 1000); // 15 minutes
```
to:
```typescript
  const expiresOn = new Date(now.getTime() + 5 * 60 * 1000); // 5 minutes
```

- [ ] **Step 3: Commit**

```bash
git add backend/src/shared/services/sasService.ts
git commit -m "fix: remove create permission from upload SAS, reduce view SAS expiry to 5 min"
```

---

## Task 4: Fix telemetry initialization for HTTP handlers (C5)

**Files:**
- Modify: `backend/src/shared/services/telemetryService.ts`

- [ ] **Step 1: Auto-initialize telemetry at module load time**

Replace `telemetryService.ts` with auto-initialization:

```typescript
import * as appInsights from 'applicationinsights';

let isInitialized = false;

export function initTelemetry(): void {
  if (isInitialized) return;
  const connectionString = process.env.APPLICATIONINSIGHTS_CONNECTION_STRING;
  if (connectionString) {
    appInsights.setup(connectionString)
      .setAutoCollectRequests(true)
      .setAutoCollectPerformance(true)
      .setAutoCollectExceptions(true)
      .setAutoCollectDependencies(true)
      .start();
    isInitialized = true;
  } else {
    console.warn('APPLICATIONINSIGHTS_CONNECTION_STRING not set — telemetry disabled');
  }
}

// Auto-initialize on module load so HTTP handlers get telemetry
initTelemetry();

export function trackEvent(name: string, properties?: Record<string, string>): void {
  if (!isInitialized) return;
  appInsights.defaultClient?.trackEvent({ name, properties });
}

export function trackError(error: Error, properties?: Record<string, string>): void {
  if (!isInitialized) return;
  appInsights.defaultClient?.trackException({ exception: error, properties });
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/shared/services/telemetryService.ts
git commit -m "fix: auto-initialize telemetry at module load for HTTP handlers"
```

---

## Task 5: Fix TLS certificate validation on database connection (C6)

**Files:**
- Modify: `backend/src/shared/services/dbService.ts:16,13,20`

- [ ] **Step 1: Enable TLS cert validation and reduce pool size**

In `dbService.ts`, change line 16:
```typescript
    ssl: { rejectUnauthorized: false },
```
to:
```typescript
    ssl: { rejectUnauthorized: true },
```

Also change line 13 (pool size for consumption plan):
```typescript
    max: 20,
```
to:
```typescript
    max: 5,
```

- [ ] **Step 2: Sanitize pool error logging**

Change line 20:
```typescript
    console.error('Unexpected pool error:', err.message);
```
to:
```typescript
    console.error('Unexpected pool error:', err.code ?? 'UNKNOWN');
```

- [ ] **Step 3: Commit**

```bash
git add backend/src/shared/services/dbService.ts
git commit -m "fix: enable TLS cert validation, reduce pool size, sanitize error logs"
```

---

## Task 6: Fix auth middleware to use typed errors (C7)

**Files:**
- Modify: `backend/src/shared/middleware/authMiddleware.ts:1,32,40,45,59,69`
- Modify: `backend/src/shared/middleware/errorHandler.ts:11-15`

- [ ] **Step 1: Import typed errors in authMiddleware**

Add to imports in `authMiddleware.ts`:
```typescript
import { UnauthorizedError, NotFoundError } from '../utils/errors';
```

- [ ] **Step 2: Replace all raw Error throws with typed errors**

Replace all occurrences of:
```typescript
throw new Error('UNAUTHORIZED');
```
with:
```typescript
throw new UnauthorizedError();
```

Replace:
```typescript
throw new Error('USER_NOT_FOUND');
```
with:
```typescript
throw new NotFoundError('user');
```

- [ ] **Step 3: Remove fragile string-matching in errorHandler**

In `errorHandler.ts`, remove lines 11-15 (the `error.message === 'UNAUTHORIZED'` check). The `AppError` instanceof check on line 7 now handles these since `UnauthorizedError` and `NotFoundError` extend `AppError`.

- [ ] **Step 4: Sanitize unhandled error logging**

In `errorHandler.ts` line 24, change:
```typescript
console.error('Unhandled error:', error.message);
```
to:
```typescript
console.error('Unhandled error:', error.name, error.constructor.name);
```

- [ ] **Step 5: Commit**

```bash
git add backend/src/shared/middleware/authMiddleware.ts backend/src/shared/middleware/errorHandler.ts
git commit -m "fix: use typed errors in auth middleware, remove fragile string matching"
```

---

## Task 7: Fix Flutter PhotoModel — add status field (C8)

**Files:**
- Modify: `app/lib/models/photo_model.dart`

- [ ] **Step 1: Add status field**

Add field after `fileSizeBytes`:
```dart
  final String status;
```

Add to constructor (required):
```dart
  required this.status,
```

Add to `fromJson`:
```dart
  status: json['status'] as String? ?? 'active',
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/models/photo_model.dart
git commit -m "fix: add missing status field to PhotoModel"
```

---

## Task 8: Fix deep link host mismatch (C9)

**Files:**
- Modify: `app/lib/core/constants/app_constants.dart:41`
- Modify: `app/lib/core/constants/environment.dart:13,28`
- Modify: `app/lib/features/circles/presentation/invite_screen.dart:26`

- [ ] **Step 1: Fix app_constants.dart**

Change line 41:
```dart
  static const deepLinkHost = 'clique-pix.com';
```
to:
```dart
  static const deepLinkHost = 'cliquepix.app';
```

- [ ] **Step 2: Fix environment.dart**

Change line 13 (prod API URL):
```dart
        return 'https://api.clique-pix.com';
```
to:
```dart
        return 'https://api.cliquepix.app';
```

Change line 28:
```dart
  static const deepLinkDomain = 'clique-pix.com';
```
to:
```dart
  static const deepLinkDomain = 'cliquepix.app';
```

- [ ] **Step 3: Fix invite_screen.dart**

Change line 26:
```dart
          final inviteUrl = 'https://clique-pix.com/invite/${circle.inviteCode}';
```
to:
```dart
          final inviteUrl = 'https://cliquepix.app/invite/${circle.inviteCode}';
```

- [ ] **Step 4: Commit**

```bash
git add app/lib/core/constants/app_constants.dart app/lib/core/constants/environment.dart app/lib/features/circles/presentation/invite_screen.dart
git commit -m "fix: correct deep link host to cliquepix.app per spec"
```

---

## Task 9: Fix auth interceptor 401 retry (C10)

**Files:**
- Modify: `app/lib/services/auth_interceptor.dart`

- [ ] **Step 1: Inject parent Dio and use it for retry**

Replace `auth_interceptor.dart` contents:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'token_storage_service.dart';

class AuthInterceptor extends Interceptor {
  final Ref ref;
  final Dio dio;

  AuthInterceptor({required this.ref, required this.dio});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final tokenStorage = ref.read(tokenStorageServiceProvider);
    final accessToken = await tokenStorage.getAccessToken();
    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      try {
        final tokenStorage = ref.read(tokenStorageServiceProvider);
        final refreshed = await tokenStorage.refreshToken();
        if (refreshed) {
          final accessToken = await tokenStorage.getAccessToken();
          err.requestOptions.headers['Authorization'] = 'Bearer $accessToken';
          final response = await dio.fetch(err.requestOptions);
          return handler.resolve(response);
        }
      } catch (_) {
        // Refresh failed, propagate original error
      }
    }
    handler.next(err);
  }
}
```

- [ ] **Step 2: Update ApiClient to pass Dio instance to AuthInterceptor**

In `app/lib/services/api_client.dart`, change the interceptor creation:

```dart
    dio.interceptors.addAll([
      AuthInterceptor(ref: ref, dio: dio),
      ErrorInterceptor(),
      RetryInterceptor(dio: dio),
    ]);
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/auth_interceptor.dart app/lib/services/api_client.dart
git commit -m "fix: auth interceptor uses parent Dio for 401 retry instead of bare instance"
```

---

## Task 10: Wire auth repository — MSAL scaffolding + signOut cleanup (C11, C12)

**Files:**
- Modify: `app/lib/features/auth/domain/auth_repository.dart`
- Modify: `app/lib/features/auth/presentation/auth_providers.dart`
- Modify: `app/lib/services/token_storage_service.dart:67-71`

- [ ] **Step 1: Wire authApiProvider to actual Dio**

In `auth_providers.dart`, replace lines 7-10:
```dart
final authApiProvider = Provider<AuthApi>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthApi(apiClient.dio);
});
```

Add the import at the top:
```dart
import '../../../services/api_client.dart';
```

- [ ] **Step 2: Add apiClientProvider if not exists**

Check if `apiClientProvider` exists. If not, add to `api_client.dart`:
```dart
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: Environment.apiBaseUrl, ref: ref);
});
```

With import:
```dart
import '../core/constants/environment.dart';
```

- [ ] **Step 3: Wire token refresh through auth repository**

In `token_storage_service.dart`, replace the `refreshToken` stub with a callback:

```dart
  Future<bool> Function()? _refreshCallback;

  void setRefreshCallback(Future<bool> Function() callback) {
    _refreshCallback = callback;
  }

  Future<bool> refreshToken() async {
    if (_refreshCallback != null) {
      return _refreshCallback!();
    }
    return false;
  }
```

- [ ] **Step 4: Wire signOut to cancel background jobs**

In `auth_repository.dart`, update `signOut`:

```dart
  Future<void> signOut() async {
    await AlarmRefreshService.cancelRefresh();
    await BackgroundTokenService.cancel();
    await tokenStorage.clearAll();
  }
```

Add imports:
```dart
import 'alarm_refresh_service.dart';
import 'background_token_service.dart';
```

- [ ] **Step 5: Fix error display in auth_providers.dart**

Change line 44:
```dart
      state = AuthError(e.toString());
```
to:
```dart
      state = const AuthError('Sign in failed. Please try again.');
```

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/auth/domain/auth_repository.dart app/lib/features/auth/presentation/auth_providers.dart app/lib/services/token_storage_service.dart app/lib/services/api_client.dart
git commit -m "fix: wire auth providers, token refresh callback, signOut cancels background jobs"
```

---

## Task 11: Fix auth route guard (C13)

**Files:**
- Modify: `app/lib/core/routing/app_router.dart:19-26`

- [ ] **Step 1: Connect redirect to auth state**

Replace the `routerProvider` definition:

```dart
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/circles',
    redirect: (context, state) {
      final isAuthenticated = authState is AuthAuthenticated;
      final isLoginRoute = state.matchedLocation == '/login';
      final isInviteRoute = state.matchedLocation.startsWith('/invite/');

      if (!isAuthenticated && !isLoginRoute && !isInviteRoute) {
        return '/login';
      }
      if (isAuthenticated && isLoginRoute) {
        return '/circles';
      }
      return null;
    },
```

Add imports:
```dart
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/auth_providers.dart';
```

- [ ] **Step 2: Fix inviteCode nullable parameter**

Change line 35:
```dart
          inviteCode: state.pathParameters['inviteCode'],
```
to:
```dart
          inviteCode: state.pathParameters['inviteCode']!,
```

And update `JoinCircleScreen` constructor to require non-null:
```dart
  final String inviteCode;
  const JoinCircleScreen({super.key, required this.inviteCode});
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/core/routing/app_router.dart app/lib/features/circles/presentation/join_circle_screen.dart
git commit -m "fix: add auth route guard, fix inviteCode nullability"
```

---

## Task 12: Fix missing backend telemetry events (H1, H2, H5)

**Files:**
- Modify: `backend/src/functions/photos.ts` (after notification send)
- Modify: `backend/src/functions/timers.ts:49,139`

- [ ] **Step 1: Add notification_sent/notification_send_failed tracking in photos.ts**

After the FCM send block in `confirmUpload` (after line 241), add:

```typescript
      // Track notification telemetry
      const successCount = tokens.length - failedTokens.length;
      if (successCount > 0) {
        trackEvent('notification_sent', { eventId, photoId, count: String(successCount) });
      }
      if (failedTokens.length > 0) {
        trackEvent('notification_send_failed', { eventId, photoId, count: String(failedTokens.length) });
      }
```

- [ ] **Step 2: Add event_expired telemetry in timers.ts**

After line 47 in `timers.ts` (after the event status UPDATE), add:

```typescript
  const expiredEvents = await query<{ count: number }>(
    `SELECT COUNT(*)::int AS count FROM events
     WHERE status = 'expired' AND expires_at < NOW()
     AND NOT EXISTS (SELECT 1 FROM photos WHERE event_id = events.id AND status = 'active')`,
  );
  // Note: this counts all currently-expired events, but the trackEvent documents the batch
  trackEvent('event_expired', { count: String(deletedCount > 0 ? 1 : 0) });
```

Actually simpler — use RETURNING on the UPDATE:

Change lines 41-47 to:
```typescript
  const expiredEventRows = await query<{ id: string }>(
    `UPDATE events SET status = 'expired'
     WHERE status = 'active' AND expires_at < NOW()
     AND NOT EXISTS (
       SELECT 1 FROM photos WHERE event_id = events.id AND status = 'active'
     )
     RETURNING id`,
  );

  if (expiredEventRows.length > 0) {
    trackEvent('event_expired', { count: String(expiredEventRows.length) });
  }
```

- [ ] **Step 3: Fix notifyExpiring telemetry event name**

In `timers.ts` line 139, change:
```typescript
  trackEvent('expiration_notifications_sent', { count: String(notifiedCount) });
```
to:
```typescript
  trackEvent('notification_sent', { type: 'event_expiring', count: String(notifiedCount) });
```

- [ ] **Step 4: Commit**

```bash
git add backend/src/functions/photos.ts backend/src/functions/timers.ts
git commit -m "fix: add missing telemetry events (notification_sent, event_expired)"
```

---

## Task 13: Fix joinCircle circleId validation (H3) + Flutter join flow (H15)

**Files:**
- Modify: `backend/src/functions/circles.ts:133-187`
- Modify: `app/lib/features/circles/domain/circles_repository.dart:31-37`
- Modify: `app/lib/features/circles/data/circles_api.dart:28-34`

- [ ] **Step 1: Add circleId validation in backend joinCircle**

After line 136 in `circles.ts`, add:

```typescript
    const circleId = req.params.circleId;
    if (!circleId || !isValidUUID(circleId)) {
      throw new ValidationError('A valid circle ID is required.');
    }
```

After finding the circle by invite code (line 148), add:
```typescript
    if (circle.id !== circleId) {
      throw new ValidationError('Invite code does not match the specified circle.');
    }
```

- [ ] **Step 2: Fix Flutter circles_repository to get circleId from invite info**

In `circles_repository.dart`, the `joinByInviteCode` needs a two-step approach. Since the backend's `joinCircle` now validates circleId matches the invite code, we need to look up the circle first. However, the simpler fix is to have the backend accept the invite code regardless of circleId match — since the backend already looks up by invite code. Let's remove the circleId validation mismatch check and just validate it's a UUID:

Actually, the cleanest approach: make the Flutter client send the correct circleId. Since `JoinCircleScreen` only has an invite code and not a circleId, we should update the backend to not require circleId matching — just validate UUID format:

Remove the `circle.id !== circleId` check added above. Keep only the UUID validation. Then fix the Flutter side:

In `circles_api.dart`, add a new method that doesn't need circleId:
```dart
  Future<Map<String, dynamic>> joinByInviteCode(String inviteCode) async {
    final response = await dio.post(
      '/api/circles/_/join',
      data: {'invite_code': inviteCode},
    );
    return response.data['data'] as Map<String, dynamic>;
  }
```

Wait — this sends `_` which fails UUID validation. Better approach: update backend to accept a special path or skip UUID check on circleId for join when invite_code is provided.

**Simplest correct fix:** Remove UUID validation on circleId for the join endpoint since the circle is looked up by invite_code anyway. The circleId param is ignored.

In `circles.ts` joinCircle, DON'T add UUID validation for circleId. The endpoint already works correctly by looking up via invite_code. The circleId in the URL is architecturally unnecessary but harmless.

In `circles_repository.dart`, change:
```dart
  Future<CircleModel> joinByInviteCode(String inviteCode) async {
    final data = await api.joinByInviteCode(inviteCode);
    return CircleModel.fromJson(data);
  }
```

In `circles_api.dart`, add:
```dart
  Future<Map<String, dynamic>> joinByInviteCode(String inviteCode) async {
    // circleId is not validated on the join endpoint — lookup is by invite_code
    final response = await dio.post(
      '${ApiEndpoints.circles}/_/join',
      data: {'invite_code': inviteCode},
    );
    return response.data['data'] as Map<String, dynamic>;
  }
```

- [ ] **Step 3: Commit**

```bash
git add backend/src/functions/circles.ts app/lib/features/circles/domain/circles_repository.dart app/lib/features/circles/data/circles_api.dart
git commit -m "fix: joinCircle uses invite_code lookup, fix Flutter join flow"
```

---

## Task 14: Fix image compression parameters (H13)

**Files:**
- Modify: `app/lib/features/photos/domain/image_compression_service.dart:16-17`

- [ ] **Step 1: Change minWidth/minHeight to maxWidth/maxHeight**

In `image_compression_service.dart` lines 16-17, change:
```dart
      minWidth: AppConstants.maxImageDimension,
      minHeight: AppConstants.maxImageDimension,
```
to:
```dart
      minWidth: 1, // No minimum
      minHeight: 1, // No minimum
```

Note: `flutter_image_compress` uses `minWidth`/`minHeight` as the TARGET dimensions (misleading API name). When the image is larger, it downscales. When smaller, it upscales TO these dimensions. To avoid upscaling, we need a different approach.

Actually, the correct approach with `flutter_image_compress` is to check dimensions first and only compress if needed:

```dart
  Future<({File file, int width, int height})> compressImage(File sourceFile) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath = '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    // Get source image dimensions to avoid upscaling
    final sourceBytes = await sourceFile.readAsBytes();
    final sourceImage = await decodeImageFromList(sourceBytes);
    final srcWidth = sourceImage.width;
    final srcHeight = sourceImage.height;

    // Only constrain if image exceeds max dimension
    final maxDim = AppConstants.maxImageDimension;
    int targetWidth = srcWidth;
    int targetHeight = srcHeight;
    if (srcWidth > maxDim || srcHeight > maxDim) {
      if (srcWidth >= srcHeight) {
        targetWidth = maxDim;
        targetHeight = (srcHeight * maxDim / srcWidth).round();
      } else {
        targetHeight = maxDim;
        targetWidth = (srcWidth * maxDim / srcHeight).round();
      }
    }

    final result = await FlutterImageCompress.compressAndGetFile(
      sourceFile.absolute.path,
      targetPath,
      quality: AppConstants.jpegQuality,
      minWidth: targetWidth,
      minHeight: targetHeight,
      format: CompressFormat.jpeg,
      keepExif: false,
    );

    if (result == null) {
      throw Exception('Image compression failed');
    }

    final compressedFile = File(result.path);
    final fileSize = await compressedFile.length();

    if (fileSize > AppConstants.maxFileSizeBytes) {
      await compressedFile.delete();
      throw Exception('Image too large after compression (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB). Maximum is 10MB.');
    }

    return (
      file: compressedFile,
      width: targetWidth,
      height: targetHeight,
    );
  }
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/photos/domain/image_compression_service.dart
git commit -m "fix: constrain max image dimension without upscaling small images"
```

---

## Task 15: Fix blob upload service — stream entire file, not byte-by-byte (H14)

**Files:**
- Modify: `app/lib/features/photos/domain/blob_upload_service.dart:14-16`

- [ ] **Step 1: Fix the upload to send bytes directly**

Replace the `uploadToBlob` method:

```dart
  Future<void> uploadToBlob(String sasUrl, File file) async {
    final bytes = await file.readAsBytes();

    await _dio.put(
      sasUrl,
      data: bytes,
      options: Options(
        headers: {
          'x-ms-blob-type': 'BlockBlob',
          'Content-Type': 'image/jpeg',
          'Content-Length': bytes.length,
        },
      ),
    );
  }
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/photos/domain/blob_upload_service.dart
git commit -m "fix: upload bytes directly instead of streaming one byte at a time"
```

---

## Task 16: Fix reaction removal — track reaction IDs (H12)

**Files:**
- Modify: `app/lib/models/photo_model.dart`
- Modify: `app/lib/features/photos/presentation/reaction_bar_widget.dart:53-55`

- [ ] **Step 1: Change userReactions from List<String> to List<Map>**

In `photo_model.dart`, change:
```dart
  final List<String> userReactions;
```
to:
```dart
  final List<({String id, String type})> userReactions;
```

Update `fromJson`:
```dart
      userReactions: (json['user_reactions'] as List<dynamic>?)
          ?.map((e) {
            if (e is String) return (id: '', type: e);
            final m = e as Map<String, dynamic>;
            return (id: m['id'] as String? ?? '', type: m['reaction_type'] as String);
          }).toList() ?? [],
```

Update constructor default:
```dart
    this.userReactions = const [],
```

- [ ] **Step 2: Update ReactionBarWidget to use reaction IDs**

In `reaction_bar_widget.dart`, update `_userReactions` to track IDs:

Change line 26:
```dart
  late Map<String, String> _userReactionIds; // type -> id
```

In `initState`:
```dart
    _userReactionIds = {};
    for (final r in widget.userReactions) {
      _userReactionIds[r.type] = r.id;
    }
    _userReactions = Set.from(_userReactionIds.keys);
```

In `_toggleReaction`, change the removal call:
```dart
      if (wasActive) {
        final reactionId = _userReactionIds[type];
        if (reactionId != null && reactionId.isNotEmpty) {
          await repo.removeReaction(widget.photoId, reactionId);
        }
      }
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/models/photo_model.dart app/lib/features/photos/presentation/reaction_bar_widget.dart
git commit -m "fix: track reaction IDs for proper removal via DELETE endpoint"
```

---

## Task 17: Fix AvatarWidget to use CachedNetworkImageProvider (H17)

**Files:**
- Modify: `app/lib/widgets/avatar_widget.dart:1,25`

- [ ] **Step 1: Replace NetworkImage with CachedNetworkImageProvider**

Add import:
```dart
import 'package:cached_network_image/cached_network_image.dart';
```

Change line 25:
```dart
        backgroundImage: NetworkImage(imageUrl!),
```
to:
```dart
        backgroundImage: CachedNetworkImageProvider(imageUrl!),
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/widgets/avatar_widget.dart
git commit -m "fix: use CachedNetworkImageProvider in AvatarWidget per spec"
```

---

## Task 18: Fix CreateCircleScreen button state (M8)

**Files:**
- Modify: `app/lib/features/circles/presentation/create_circle_screen.dart`

- [ ] **Step 1: Add TextEditingController listener**

In `_CreateCircleScreenState`, add `initState`:

```dart
  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/circles/presentation/create_circle_screen.dart
git commit -m "fix: create circle button updates enabled state as user types"
```

---

## Task 19: Fix reactions.ts dynamic imports (L2) + telemetry key consistency

**Files:**
- Modify: `backend/src/functions/reactions.ts:8,15,40,54,65`

- [ ] **Step 1: Add ValidationError to static imports**

Change line 8:
```typescript
import { NotFoundError, ForbiddenError } from '../shared/utils/errors';
```
to:
```typescript
import { NotFoundError, ForbiddenError, ValidationError } from '../shared/utils/errors';
```

- [ ] **Step 2: Replace dynamic imports with static ValidationError**

Lines 15 and 54: replace `throw new (await import('../shared/utils/errors')).ValidationError(...)` with `throw new ValidationError(...)`.

- [ ] **Step 3: Fix telemetry property keys to camelCase**

Line 40:
```typescript
    trackEvent('reaction_added', { photo_id: photoId, reaction_type: reactionType });
```
to:
```typescript
    trackEvent('reaction_added', { photoId, reactionType });
```

Line 65:
```typescript
    trackEvent('reaction_removed', { photo_id: photoId });
```
to:
```typescript
    trackEvent('reaction_removed', { photoId, reactionId });
```

- [ ] **Step 4: Commit**

```bash
git add backend/src/functions/reactions.ts
git commit -m "fix: use static imports, consistent camelCase telemetry keys"
```

---

## Task 20: Fix duplicate expiration notifications (M1)

**Files:**
- Modify: `backend/src/functions/timers.ts:87-93`

- [ ] **Step 1: Add deduplication check**

Change the expiring events query (lines 87-93) to exclude events that already have an `event_expiring` notification within the last 20 hours:

```typescript
  const expiringEvents = await query<any>(
    `SELECT e.id, e.name, e.circle_id, e.expires_at
     FROM events e
     WHERE e.status = 'active'
       AND e.expires_at > NOW() + INTERVAL '23 hours'
       AND e.expires_at <= NOW() + INTERVAL '25 hours'
       AND NOT EXISTS (
         SELECT 1 FROM notifications n
         WHERE n.type = 'event_expiring'
           AND n.payload_json->>'event_id' = e.id::text
           AND n.created_at > NOW() - INTERVAL '20 hours'
       )`,
  );
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/functions/timers.ts
git commit -m "fix: deduplicate expiring-soon notifications across hourly runs"
```

---

## Task 21: Fix ErrorInterceptor to preserve API error envelope (M10)

**Files:**
- Modify: `app/lib/services/error_interceptor.dart`

- [ ] **Step 1: Preserve error details when rejecting**

Replace `error_interceptor.dart`:

```dart
import 'package:dio/dio.dart';

class ErrorInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      if (data['error'] != null && data['data'] == null) {
        final error = data['error'] as Map<String, dynamic>;
        handler.reject(
          DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
            message: error['message'] as String? ?? 'Unknown API error',
          ),
        );
        return;
      }
    }
    handler.next(response);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/services/error_interceptor.dart
git commit -m "fix: preserve API error message in ErrorInterceptor rejection"
```

---
