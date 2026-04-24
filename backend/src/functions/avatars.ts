import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRequest } from '../shared/middleware/authMiddleware';
import { handleError } from '../shared/middleware/errorHandler';
import { successResponse } from '../shared/utils/response';
import { queryOne, execute } from '../shared/services/dbService';
import { trackEvent } from '../shared/services/telemetryService';
import {
  blobExists,
  getBlobProperties,
  downloadBlob,
  uploadBlob,
  deleteBlob,
} from '../shared/services/blobService';
import { generateUploadSas } from '../shared/services/sasService';
import { ValidationError, NotFoundError } from '../shared/utils/errors';
import { User } from '../shared/models/user';
import { buildAuthUserResponse } from '../shared/services/avatarEnricher';

// Upload-SAS expiry: 5 minutes (photos default). Short because clients
// upload immediately after calling this endpoint; they don't need a long
// window.
const AVATAR_UPLOAD_SAS_EXPIRY_SECONDS = 5 * 60;

// Server-side avatar size limit. Client-side compression targets ~100 KB
// but we accept up to 3 MB as a safety net (covers poor compression on
// older devices or the web's browser-image-compression fallbacks).
const AVATAR_MAX_BYTES = 3 * 1024 * 1024;

// Thumb size (matches the Flutter AvatarWidget's card-size render target:
// 36pt feed avatars, 44pt DM headers, 88pt profile hero). 128px is enough
// for all card sizes at 2x retina; hero uses the full original.
const AVATAR_THUMB_DIMENSION = 128;

// Snooze: user tapped "Maybe Later" on the welcome prompt. Re-prompt
// eligible after 7 days.
const PROMPT_SNOOZE_DAYS = 7;

function avatarOriginalPath(userId: string): string {
  return `avatars/${userId}/original.jpg`;
}

function avatarThumbPath(userId: string): string {
  return `avatars/${userId}/thumb.jpg`;
}

// POST /api/users/me/avatar/upload-url
async function getAvatarUploadUrl(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const blobPath = avatarOriginalPath(authUser.id);
    const uploadUrl = await generateUploadSas(blobPath, AVATAR_UPLOAD_SAS_EXPIRY_SECONDS);

    trackEvent('avatar_upload_url_issued', { userId: authUser.id });

    return successResponse({
      upload_url: uploadUrl,
      blob_path: blobPath,
    });
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// POST /api/users/me/avatar
// Client PUTs to the SAS URL first, then calls this to confirm. Server
// verifies the blob, generates a 128px thumbnail via sharp, and updates
// the users row. The blob path is fixed per-user so each new upload
// supersedes the previous one (no accumulation, no orphan tracking).
async function confirmAvatar(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const originalPath = avatarOriginalPath(authUser.id);
    const thumbPath = avatarThumbPath(authUser.id);

    // 1. Verify the blob actually exists at the expected path.
    const exists = await blobExists(originalPath);
    if (!exists) {
      throw new NotFoundError('avatar');
    }

    // 2. Validate size + content-type by reading blob properties. We trust
    // the blob's Content-Type header (set by the client during upload) but
    // cross-check the buffer magic bytes would be overkill for avatars.
    const props = await getBlobProperties(originalPath);
    const sizeBytes = props.contentLength ?? 0;
    if (sizeBytes > AVATAR_MAX_BYTES) {
      // Clean up the oversized blob so the client can retry cleanly.
      await deleteBlob(originalPath);
      throw new ValidationError(`Avatar must be smaller than 3 MB. Uploaded: ${Math.round(sizeBytes / 1024)} KB.`);
    }
    const contentType = props.contentType ?? '';
    if (contentType !== 'image/jpeg' && contentType !== 'image/png') {
      await deleteBlob(originalPath);
      throw new ValidationError('Avatar must be a JPEG or PNG image.');
    }

    // 3. Generate the 128px thumbnail inline. Unlike event photos (where
    // the thumbnail is fire-and-forget async), we do this synchronously
    // because the client expects the thumb URL to be ready when we return.
    // The operation is cheap (~50-100 ms for a 512px input on sharp).
    const sharp = (await import('sharp')).default;
    const originalBuffer = await downloadBlob(originalPath);
    const thumbBuffer = await sharp(originalBuffer)
      .resize({
        width: AVATAR_THUMB_DIMENSION,
        height: AVATAR_THUMB_DIMENSION,
        fit: 'cover',
      })
      .jpeg({ quality: 75 })
      .toBuffer();
    await uploadBlob(thumbPath, thumbBuffer, 'image/jpeg');

    // 4. Update the user row. avatar_updated_at changes every upload, which
    // seeds the client-side cache key so old cached images are invalidated.
    const user = await queryOne<User>(
      `UPDATE users
       SET avatar_blob_path = $1,
           avatar_thumb_blob_path = $2,
           avatar_updated_at = NOW(),
           updated_at = NOW()
       WHERE id = $3
       RETURNING *`,
      [originalPath, thumbPath, authUser.id],
    );
    if (!user) throw new NotFoundError('user');

    trackEvent('avatar_uploaded', {
      userId: authUser.id,
      sizeBytes: String(sizeBytes),
      contentType,
    });

    return successResponse(await buildAuthUserResponse(user));
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// DELETE /api/users/me/avatar
async function deleteAvatar(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const originalPath = avatarOriginalPath(authUser.id);
    const thumbPath = avatarThumbPath(authUser.id);

    // Best-effort blob cleanup. deleteIfExists is idempotent so a missing
    // blob (e.g., thumb never generated because original upload failed) is
    // fine.
    await Promise.all([deleteBlob(originalPath), deleteBlob(thumbPath)]);

    const user = await queryOne<User>(
      `UPDATE users
       SET avatar_blob_path = NULL,
           avatar_thumb_blob_path = NULL,
           avatar_updated_at = NOW(),
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [authUser.id],
    );
    if (!user) throw new NotFoundError('user');

    trackEvent('avatar_removed', { userId: authUser.id });

    return successResponse(await buildAuthUserResponse(user));
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// PATCH /api/users/me/avatar/frame
// Changes only the frame preset (0..4). Works regardless of whether a
// custom avatar is uploaded — preset 1..4 overrides the initials-gradient
// fallback's name-hash color.
async function updateAvatarFrame(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const body = (await req.json()) as { frame_preset?: number } | null;
    const preset = body?.frame_preset;
    if (typeof preset !== 'number' || !Number.isInteger(preset) || preset < 0 || preset > 4) {
      throw new ValidationError('frame_preset must be an integer between 0 and 4.');
    }

    const user = await queryOne<User>(
      `UPDATE users
       SET avatar_frame_preset = $1,
           updated_at = NOW()
       WHERE id = $2
       RETURNING *`,
      [preset, authUser.id],
    );
    if (!user) throw new NotFoundError('user');

    trackEvent('avatar_frame_changed', { userId: authUser.id, preset: String(preset) });

    return successResponse(await buildAuthUserResponse(user));
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

// POST /api/users/me/avatar-prompt
// Handles the Maybe Later / No Thanks choices from the first-sign-in
// welcome prompt. Yes needs no endpoint — the subsequent upload confirm
// sets avatar_blob_path which implicitly suppresses future prompts via
// shouldPromptForAvatar.
async function updateAvatarPrompt(req: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const authUser = await authenticateRequest(req);
    const body = (await req.json()) as { action?: string } | null;
    const action = body?.action;

    if (action === 'dismiss') {
      await execute(
        `UPDATE users SET avatar_prompt_dismissed = TRUE, updated_at = NOW() WHERE id = $1`,
        [authUser.id],
      );
      trackEvent('avatar_prompt_dismissed', { userId: authUser.id });
    } else if (action === 'snooze') {
      await execute(
        `UPDATE users
         SET avatar_prompt_snoozed_until = NOW() + INTERVAL '${PROMPT_SNOOZE_DAYS} days',
             updated_at = NOW()
         WHERE id = $1`,
        [authUser.id],
      );
      trackEvent('avatar_prompt_snoozed', { userId: authUser.id, days: String(PROMPT_SNOOZE_DAYS) });
    } else {
      throw new ValidationError(`action must be 'dismiss' or 'snooze'; got '${action ?? ''}'.`);
    }

    const user = await queryOne<User>('SELECT * FROM users WHERE id = $1', [authUser.id]);
    if (!user) throw new NotFoundError('user');

    return successResponse(await buildAuthUserResponse(user));
  } catch (error) {
    return handleError(error, context.invocationId);
  }
}

app.http('getAvatarUploadUrl', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'users/me/avatar/upload-url',
  handler: getAvatarUploadUrl,
});

app.http('confirmAvatar', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'users/me/avatar',
  handler: confirmAvatar,
});

app.http('deleteAvatar', {
  methods: ['DELETE'],
  authLevel: 'anonymous',
  route: 'users/me/avatar',
  handler: deleteAvatar,
});

app.http('updateAvatarFrame', {
  methods: ['PATCH'],
  authLevel: 'anonymous',
  route: 'users/me/avatar/frame',
  handler: updateAvatarFrame,
});

app.http('updateAvatarPrompt', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'users/me/avatar-prompt',
  handler: updateAvatarPrompt,
});
