import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { verifyJwtAllowExpired } from '../shared/middleware/authMiddleware';
import { initTelemetry, trackEvent } from '../shared/services/telemetryService';
import { successResponse, errorResponse } from '../shared/utils/response';

// ============================================================================
// POST /api/telemetry/auth
// ============================================================================
// Accepts token-refresh / auth-lifecycle events from the Flutter client. The
// caller's access token may be expiring or recently expired (that is the
// whole point of these events), so we validate the JWT SIGNATURE only and
// ignore the `exp` claim. If the signature is invalid or the token is not
// from our CIAM tenant, the request is rejected.
//
// APIM applies a 30/min/IP rate limit on this route.
//
// Body: { event: string, errorCode?: string, platform: 'ios'|'android',
//         extra?: Record<string,string> }
const ALLOWED_EVENTS = new Set([
  'battery_exempt_prompted',
  'battery_exempt_granted',
  'silent_push_received',
  'silent_push_refresh_success',
  'silent_push_refresh_failed',
  'silent_push_fallback_flag_set',
  'foreground_stale_check',
  'foreground_refresh_success',
  'foreground_refresh_failed',
  'wm_task_fired',
  'wm_refresh_success',
  'wm_refresh_failed',
  'welcome_back_shown',
  'welcome_back_continue',
  'welcome_back_switch_account',
  'cold_start_relogin_required',
]);

async function recordAuthTelemetry(
  req: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  initTelemetry();

  const authHeader = req.headers.get('authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return errorResponse('UNAUTHORIZED', 'Authentication required.', 401, context.invocationId);
  }

  let userId: string;
  try {
    const payload = await verifyJwtAllowExpired(authHeader.slice(7));
    userId = payload.userId;
  } catch (_err) {
    return errorResponse('UNAUTHORIZED', 'Invalid token signature.', 401, context.invocationId);
  }

  let body: { event?: string; errorCode?: string; platform?: string; extra?: Record<string, string> };
  try {
    body = (await req.json()) as typeof body;
  } catch {
    return errorResponse('VALIDATION_ERROR', 'Invalid JSON body.', 400, context.invocationId);
  }

  if (!body.event || !ALLOWED_EVENTS.has(body.event)) {
    return errorResponse(
      'VALIDATION_ERROR',
      'Unknown or missing event name.',
      400,
      context.invocationId,
    );
  }

  if (body.platform !== 'ios' && body.platform !== 'android') {
    return errorResponse(
      'VALIDATION_ERROR',
      'platform must be "ios" or "android".',
      400,
      context.invocationId,
    );
  }

  const properties: Record<string, string> = {
    userId,
    platform: body.platform,
  };
  if (body.errorCode) properties.errorCode = body.errorCode.slice(0, 64);
  if (body.extra) {
    for (const [k, v] of Object.entries(body.extra)) {
      // clip to keep payload small
      properties[`x_${k}`] = String(v).slice(0, 256);
    }
  }

  trackEvent(body.event, properties);

  return successResponse({ accepted: true });
}

app.http('recordAuthTelemetry', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'telemetry/auth',
  handler: recordAuthTelemetry,
});
