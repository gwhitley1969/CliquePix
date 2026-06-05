import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { authenticateRevenueCatWebhook } from '../shared/middleware/revenuecatAuthMiddleware';
import { upsertEntitlement, type RcWebhookEvent } from '../shared/services/entitlementService';
import { trackEvent } from '../shared/services/telemetryService';
import { successResponse, errorResponse } from '../shared/utils/response';
import { UnauthorizedError } from '../shared/utils/errors';

// ============================================================================
// POST /api/internal/revenuecat-webhook
// ============================================================================
// Receives subscription lifecycle events from RevenueCat. Auth is a shared
// secret in the Authorization header (validated by revenuecatAuthMiddleware).
//
// CRITICAL invariants:
//
//   - Returns 200 within ~1 second on ANY non-auth outcome (including unknown
//     event types, no-op updates, missing user rows). RC retries with
//     exponential backoff on non-2xx, and a retry-storm would mask the
//     real problem behind queue backlog.
//
//   - Idempotent on event.id. RC retries WILL deliver the same event_id
//     multiple times. upsertEntitlement gates on (event_id changed) AND
//     (event_timestamp newer than stored) so duplicates and out-of-order
//     deliveries are safely no-op'd.
//
//   - Only the auth failure path returns non-200. Everything else is logged
//     + 200.
//
// Body shape: RC wraps the event in `{ event: { ... }, api_version: '1.0' }`.
// We unwrap and pass the inner event to the service. See entitlementService
// `RcWebhookEvent` for the fields we read.

interface RcWebhookEnvelope {
  api_version?: string;
  event?: RcWebhookEvent;
}

export async function revenuecatWebhook(
  req: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  try {
    // Auth first — if this throws, the catch returns 401 (the only non-200
    // outcome of this endpoint).
    authenticateRevenueCatWebhook(req);

    const envelope = (await req.json()) as RcWebhookEnvelope;
    const event = envelope?.event;

    if (!event || !event.id || !event.type || !event.app_user_id) {
      // Malformed payload — log and return 200 anyway so RC doesn't retry.
      // This is an integration bug on our side, not a transient issue.
      trackEvent('entitlement_webhook_malformed', {
        hasEvent: String(!!event),
      });
      context.warn('RevenueCat webhook payload missing required fields');
      return successResponse({ ignored: 'malformed' });
    }

    trackEvent('entitlement_webhook_received', {
      eventType: event.type,
      productId: event.product_id ?? 'none',
      userId: event.app_user_id,
      eventId: event.id,
    });

    const result = await upsertEntitlement(event);

    if (result.applied) {
      trackEvent(result.active ? 'entitlement_activated' : 'entitlement_deactivated', {
        source: 'webhook',
        store: event.store ?? 'none',
        productId: event.product_id ?? 'none',
        eventType: event.type,
      });
    } else {
      trackEvent('entitlement_webhook_skipped', {
        reason: result.reason,
        eventType: event.type,
      });
    }

    return successResponse({ applied: result.applied });
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      // Wrong / missing shared-secret. Surface 401 — RC's docs say it will
      // retry with exponential backoff, which is fine; the operator will
      // notice via the `apim-401` Azure Monitor alert if the secret drifts.
      trackEvent('entitlement_webhook_unauthorized');
      return errorResponse('UNAUTHORIZED', 'Webhook authentication failed.', 401);
    }
    // Unexpected error — log to App Insights and return 200 so RC does NOT
    // retry-storm this endpoint (the documented invariant above). A persistent
    // error (code bug, poison event) retried with exponential backoff would mask
    // real subscription events behind queue backlog; transient drops are
    // recovered by the client's 30s post-purchase force-sync + the 6h
    // reconciliation timer. (The most common poison case — a non-UUID
    // app_user_id — is already caught as a clean no-op in upsertEntitlement.)
    context.error('RevenueCat webhook handler error', error);
    trackEvent('entitlement_webhook_error', {
      message: error instanceof Error ? error.message : String(error),
    });
    return successResponse({ ignored: 'error' });
  }
}

app.http('revenuecatWebhook', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'internal/revenuecat-webhook',
  handler: revenuecatWebhook,
});
