export interface User {
  id: string;
  external_auth_id: string;
  display_name: string;
  email_or_phone: string;
  // Legacy column from migration 001, retained but unused post-migration 010.
  // New code reads avatar_blob_path / avatar_thumb_blob_path and emits signed
  // SAS URLs via enrichUserAvatar. A future migration 011 can drop this.
  avatar_url: string | null;
  avatar_blob_path: string | null;
  avatar_thumb_blob_path: string | null;
  avatar_updated_at: Date | null;
  avatar_frame_preset: number;
  avatar_prompt_dismissed: boolean;
  avatar_prompt_snoozed_until: Date | null;
  age_verified_at: Date | null;
  // Subscription entitlement state (migration 012). All nullable except
  // entitlement_active which defaults FALSE. Fed by RevenueCat webhooks
  // at POST /api/internal/revenuecat-webhook + reconciled every 6h by
  // entitlementReconciliationTimer.
  revenuecat_customer_id: string | null;
  entitlement_active: boolean;
  entitlement_product_id: string | null;
  entitlement_period_type: string | null;
  entitlement_will_renew: boolean | null;
  entitlement_expires_at: Date | null;
  entitlement_store: string | null;
  entitlement_last_event_id: string | null;
  entitlement_updated_at: Date | null;
  trial_ends_at: Date | null;
  created_at: Date;
  updated_at: Date;
}
