# DEPLOYMENT_STATUS.md — CLIQUE Pix v1

Last updated: 2026-06-18 (iOS PRODUCTION SUBMISSION: **first App Store production build** — `1.0.0 (9)` IPA built on the Mac (`flutter build ipa --release`, clean) and uploaded to App Store Connect via Transporter; **now in Apple review**. Carries the new **branded launch screen** (PR #67 — primary brand gradient + camera icon + white "CLIQUE Pix" wordmark, replacing Flutter's default placeholder; cleared the "default placeholder launch image" build warning). iOS build number `+9` matches Android vc9 but iOS/TestFlight numbers are tracked independently from Play. Prior 2026-06-17: ANDROID PRODUCTION: vc9 AAB (clean, upload-key signed, real `goog_` key + paywall never-blank hardening) pushed to the Play **production** track — first build with working Android billing; Google review + staged rollout pending; purchase smoke-test via License testing. ANDROID BILLING fully unblocked: **both Google clocks cleared** — subscriptions-API credential VALIDATED (was a missing "Manage orders and subscriptions" perm) **and** Payments-profile org-name verification (BlueBuildApps→Xtend-AI) approved. Play subscriptions are **created + active** (`plus_monthly`/`monthly` $3.99, `plus_annual`/`annual` $39.99 + 7-day free-trial offer) and **RTDN is wired** (Connect to Google needed a temporary Domain Restricted Sharing org-policy override — see top entry). Remaining: Android purchase smoke test on vc9 + revert the temporary Admin grant to least-privilege. Prior 2026-06-16: RevenueCat Play app created + `goog_` key wired into the client (PR #62, merged to `main`, versionCode bumped to 9); RC products/entitlement/offering fully wired for Android. See top entry. Prior — 2026-06-11: COST INCIDENT transcoder Container Apps Job billed ~$447 MTD, root-caused + mitigated. Prior same-day: app-wide lockout — all 14 users' backfilled trials expired 2026-06-09 and the Android paywall rendered a blank screen [placeholder RC key + no PaywallView fallback]; resolved same-day: trials extended +30d via SQL, reviewer lifetime promo grant live end-to-end, TWO production backend bugs fixed + deployed [webhook app_user_id resolution order, RC REST client on v1 API with a v2-only key], paywall never-blank hardening + stable-router fix on `main` pending next mobile build. Prior: Play rejection of versionCode 6 fixed [PR #52], versionCode 7 uploaded 2026-06-10 — in Google review.)

## iOS PRODUCTION SUBMISSION: 1.0.0 (9) → App Store review (2026-06-18)

**Status:** **First App Store production build.** `1.0.0 (9)` IPA built on the Mac (`flutter build ipa --release`, clean → `pub get` → `pod install` → build; automatic signing, team `4ML27KY869`, bundle `com.cliquepix.app`) and uploaded to App Store Connect via **Transporter** (Gene did the drag + Deliver). **Now in Apple review.** Carries everything on `main` as of the build plus the new branded launch screen.

**Artifact (built 2026-06-18 from `app/`):**
- IPA: `build/ios/ipa/clique_pix.ipa` (39 MB, `1.0.0 (9)`)

**What's new in this build:**
- **Branded iOS launch screen** (PR #67) — primary brand gradient (`#00C2D1 → #2563EB → #7C3AED`) + camera icon + white "CLIQUE Pix" wordmark, replacing Flutter's default placeholder. Cleared the "default placeholder launch image" build warning. Native storyboard + asset catalog only (no `flutter_native_splash`). Build + regen recipe: `HANDOFF.md §3 → "iOS launch screen (branded splash)"`.
- Rides the same `main` code as Android vc9: never-blank paywall fallback + stable router (PR #55), clique ownership lifecycle, Home grey-screen / null-FK fix, photo 3024/q88 + avatar q90 quality, #24/#25 hardening.

**Build-number note:** iOS `+9` matches Android Play vc9, but **iOS/TestFlight build numbers are tracked independently from Play.** Before each iOS build, check App Store Connect → TestFlight for the highest `+N` already uploaded under `1.0.0`; App Store Connect rejects a duplicate. Bump iOS only with `flutter build ipa --release --build-number=<next>` (overrides `CFBundleVersion` without disturbing the committed pubspec number).

**Remaining:** Apple review outcome (export-compliance/encryption questions may arrive first); attach build `1.0.0 (9)` to the App Store listing + submit for release once it clears processing. Merge PR #67 to `main` so the launch screen source ships in all future builds.

## ANDROID PRODUCTION RELEASE: vc9 → production track (2026-06-17)

**Status:** vc9 AAB built clean (upload-key signed, `1.0.0+9`, 58.3 MB) and pushed to the Play Console **production** track. **First production build with working Android billing** — carries the real `goog_` RevenueCat key (PR #62) + the paywall never-blank hardening / stable-router fix. Supersedes vc7 (uploaded 2026-06-10, was in Google review).

**Artifacts (built 2026-06-17 from `app/`, clean builds):**
- AAB (production upload): `build/app/outputs/bundle/release/app-release.aab` (58.3 MB)
- APK (sideload checks — sign-in / paywall / `Purchases.configure`): `build/app/outputs/flutter-apk/app-release.apk` (67.9 MB)

**Rollout guidance (recorded with the push):**
- **Staged rollout** (start small, not 100%) so any Android-billing issue can be **halted** rather than hitting every user at once — especially given the 2026-06-11 blank-paywall lockout this build fixes.
- **Purchase smoke test works on production:** add the test account to Play Console → Setup → **License testing** (license testers buy with no charge on any track, including production); verify a monthly + annual purchase flips the entitlement and dismisses the paywall **before** ramping to 100%.
- Production review can take hours–days; products may take time to resolve after approval (an immediate "item not available" isn't necessarily a config bug).

**Still owed:** revert the temporary Admin grant on the RC service account → least-privilege; Android tester promos (grantable in RC once a vc9 install creates their customers).

## ANDROID BILLING: fully unblocked — credentials validated, payments profile cleared, subscriptions active, RTDN wired (updated 2026-06-17)

**Status:** ✅ `goog_` Android SDK key captured + wired into the client (PR #62 **merged to `main`**, versionCode **9**) · ✅ RevenueCat Android fully configured (Play app, products, entitlement, offering packages) · ✅ **service-account credentials VALIDATED** (subscriptions-API check green) · ✅ **Payments-profile org-name verification approved 2026-06-17** · ✅ **Play subscriptions created + active** (both base plans + annual free-trial offer) · ✅ **RTDN wired** (Connect to Google succeeded after a temporary Domain Restricted Sharing override). **Both Google clocks are clear — Android billing is unblocked end-to-end.** Remaining: smoke-test a purchase on a vc9 build + revert the temporary Admin grant. The next mobile build (versionCode 9) is the first to carry the real Android key — until then Android `Purchases.configure()` short-circuited on the placeholder.

**What shipped (code):** PR #62 (`chore/android-revenuecat-key-vc9`, merged `26a0bcd`) — `app/lib/core/constants/revenuecat_constants.dart` Android key `goog_CxDvuOryuEQtBiylZjCbkabcdHF` (replaces the `goog_REPLACE_WITH` placeholder, which also disarms the `isPlaceholderKey` short-circuit so the SDK actually configures on Android) + pubspec `1.0.0+8 → 1.0.0+9`. Flutter CI green.

**RevenueCat state (verified via API, project `proj04f5314d`):**
- Apps: `Clique Pix (App Store)` `app8720f8aecb`, **`Clique Pix (Play Store)` `appbdff3c693e`** (package `com.cliquepix.clique_pix`), `Test Store`.
- Android public SDK key: **`goog_CxDvuOryuEQtBiylZjCbkabcdHF`** (public-safe, shipped in client).
- Play products (active in RC): **`plus_monthly:monthly`** (`prod346a7e0e37`), **`plus_annual:annual`** (`prod8178fcaf60`) — correct `subscriptionId:basePlanId` format.
- Entitlement `plus` (`entldcaccca2c3`): both Play products attached (6 products total incl. iOS + Test Store).
- Offering `default` (`ofrng6deb872be8`, `is_current`): **assistant attached both Play products to the packages** — `$rc_monthly` (`pkge952d5ad91f`) + `$rc_annual` (`pkge8992e56a7f`) now each carry Test+App+Play. (They were attached to the entitlement but missing from the offering packages — fixed 2026-06-16. Without it, Android packages had no purchasable product.)
- Cosmetic only: the two Play products have `display_name: null` (iOS reads "Plus Monthly"/"Plus Annual"). No API/MCP tool edits an existing product's display name — manual dashboard edit if desired; functionally irrelevant (paywall pulls titles/prices from the store at runtime).

**Google-side clocks:**
1. **Service-account "subscriptions API" permission — ✅ RESOLVED 2026-06-17.** Root cause: the account-level **"Manage orders and subscriptions"** permission was **missing** from the original grant (NOT propagation). The tell: RC's check sat at a stable **2-green / 1-red** for 24h+ (✅ inappproducts via "View app information", ✅ monetization via "View financial data", ❌ subscriptions). All three checks share one service-account JSON and one Google API (`androidpublisher.googleapis.com`), so a *stable* split isolates the cause to the single permission the red check needs — propagation would have moved all three together, then cleared together. Granting it (Gene applied **Admin (all permissions)** at the account level on `revenuecat-play@clique-pix-d7fde.iam.gserviceaccount.com` as a test) gave that permission its first real propagation window; it validated within minutes. The earlier Google Play Android Developer API enablement (GCP project `clique-pix-d7fde`) is what had turned inappproducts+monetization green. **Follow-up (security): revert Admin → the three least-privilege permissions** — "View app information and download bulk reports (read-only)", "View financial data, orders, and cancellation survey responses", **"Manage orders and subscriptions"** — then re-validate once (the SA JSON is the production credential, in gitignored `secrets/`; Admin is over-broad if it leaks).
2. **Payments-profile / org-name verification — ✅ RESOLVED 2026-06-17.** Tax was verified 2026-06-03; the identity/Payments-profile org-name change **BlueBuildApps, LLC → Xtend-AI, LLC** was approved by Google this morning. This had gated *activating/selling* subscriptions; now cleared.

**Done (2026-06-17):**
1. ✅ Play subscriptions **created + active** (Play Console → Monetize with Play → Products → Subscriptions): `plus_monthly` "CLIQUE Pix (Monthly)" $3.99 + `plus_annual` "CLIQUE Pix (Annual)" $39.99 with the 7-day free-trial offer. Both show an active base plan; base-plan IDs `monthly`/`annual` link to RC `plus_monthly:monthly` / `plus_annual:annual`. (Note: RC `get-offering-prices` reports $9.99/$79.99 — those are **Test Store** placeholder products, NOT real prices; real store prices resolve client-side at runtime.)
2. ✅ **RTDN wired** (RevenueCat → Play app → Google developer notifications → topic `Play-Store-Notifications` → Connect to Google; pasted into Play Console → Monetize with Play → Monetization setup → Real-time developer notifications; test received). **Gotcha:** Connect to Google first failed with `"One or more users named in the policy do not belong to a permitted customer"` = the **Domain Restricted Sharing** org policy (`iam.allowedPolicyMemberDomains`, on-by-default for orgs created ≥ 2024-05-03) blocking the grant of `google-play-developer-notifications@system.gserviceaccount.com`. Fix: temporarily **Override parent's policy → Allow All** on project `clique-pix-d7fde` (Cloud Console → IAM & Admin → Organization policies), re-click Connect, then re-lock (the existing IAM binding persists).

**Remaining (the short tail):**
1. **Smoke-test a purchase** on a versionCode-9 build with a Play license-test account — confirm the entitlement flips + paywall dismisses.
2. **Revert Admin → least-privilege** on the service account (see clock 1 follow-up).
3. **Android tester promos** — grant the 4 testers 1-year promos in RC → Customers once a vc9 build creates their RC customers (today the grant 404s — no customer yet).

**Not blocking / safety net:** all users on trials to **2026-07-11**; iOS path unaffected (TestFlight-ready, iOS key live). No lockout risk during the wait.

**Rollback:** PR #62 is additive (a constant + version bump); `git revert 26a0bcd` restores the placeholder. RC package attachments can be detached. No DB/infra change.

---

## FEATURE: clique ownership lifecycle (reassignment + transfer) — code complete (2026-06-16)

**Status:** ✅ code complete + **backend DEPLOYED** (`func publish`, `/api/health` 200, `transfer-ownership` 401-not-404 direct + APIM) + **migration `014` APPLIED** (verified: 0 ownerless cliques; clique `9525a0ea` → Paula `role='owner'` + `created_by`=Paula; 0 empty-orphan cliques) · ⏳ migration `015` (notification type) + a re-deploy carry the new-owner notification · ⏳ mobile UI (Make-owner + notification rendering) ships in next app build. Follow-on to the grey-screen fix (PR #59), which was the first symptom of this gap.

**Why.** Cliques had no ownership lifecycle: deleting the creator's account left the clique with members but ZERO owners (`cliques.created_by_user_id` SET NULL + the owner's `clique_members` row CASCADE-deleted), there was no transfer endpoint (`leaveClique` told owners to "Transfer ownership before leaving" but nothing implemented it), and an ownerless clique's last member leaving leaked all its media blobs. Orphan confirmed in prod: clique `9525a0ea` (Paula + Gene, both `role='member'`, no owner).

**Invariant established:** every clique with ≥1 member has exactly one `role='owner'` member, and `cliques.created_by_user_id` is kept in LOCKSTEP with it (already-installed app builds read `created_by` for their `isOwner` check, so it must stay correct — this is why we didn't switch to a role-only model).

**What shipped (code):**
- `backend/src/shared/services/cliqueOwnershipService.ts`: `selectSuccessorUserId` (longest-tenured — `joined_at ASC, user_id ASC`) + `promoteToOwner` (role + created_by lockstep).
- `deleteMe` (`auth.ts`): promote successor on owned multi-member cliques before the user-row cascade.
- `leaveClique` (`cliques.ts`): owner-leave now AUTO-PROMOTES the longest-tenured member (was a hard block); last-member-leave (any role) deletes the clique + blobs via `deleteMediaAssets` (closes the leak).
- `POST /api/cliques/{id}/transfer-ownership` — explicit hand-off (atomic single-statement `CASE` role swap + created_by). Mobile: clique-detail member overflow menu → "Make owner" / "Remove from clique".
- Migration `014_clique_ownership_backfill.sql`: promote longest-tenured for ownerless cliques + lockstep-repair `created_by`. Idempotent. ⚠️ applying it is a **production write** (Azure MCP postgres is read-only) — run via psql per `reference_prod_db_access`.
- Telemetry `clique_ownership_transferred` (`reason`: `account_deleted` | `owner_left` | `explicit`).

**Verification:** backend 0 lint errors + tsc clean + **231 jest** (+8 new `cliqueOwnership.test.ts`); Flutter `analyze` 54 baseline + **120 tests**.

**Deploy when ready:** `func azure functionapp publish func-cliquepix-fresh` (the endpoint is harmless until a client calls it) + apply `014` via psql → re-query `9525a0ea` (expect Paula `role='owner'`, `created_by`=Paula). Mobile UI rides the next app build.

**New-owner notification (added same day):** all three ownership-change paths now call `notifyNewOwner` (in-app `clique_ownership_transferred` row + FCM push "You're now the owner of X" → taps to the clique). Best-effort (try/catch) so it can never break the ownership change. Migration `015_clique_ownership_notification_type.sql` adds the type to the `notifications.type` CHECK (additive, idempotent). Client renders the new type (icon/title/tap routing in `notifications_screen.dart`). Deploying code BEFORE `015` is safe — the INSERT would just fail the CHECK and be swallowed until `015` lands.

**Still deferred:** role-as-single-source-of-truth refactor (breaks old builds' `isOwner`).

---

## CRASH FIX: post-auth grey Home screen (null creator FK) — fixed + device-verified (2026-06-16)

**Status:** ✅ root-caused + fixed on `main` working tree · ✅ **device-verified on a Samsung Galaxy Z Fold 7** (Gene, 2026-06-16 — Home renders correctly) · ⏳ ships in the next mobile build (rides versionCode 8 with the other pending Flutter fixes) · ⏳ commit/PR pending.

**The bug.** After sign-in, some users hit a **blank grey Home screen** (Flutter's silent release-mode `RenderErrorBox`). Reported on a Z Fold 7; it *looked* device-specific but was **account-data-specific**.

**Root cause (confirmed against prod DB).** One clique (`9525a0ea-5faa-428a-8404-9248a0646c07`) had **`created_by_user_id = NULL`** — the creator's account was deleted and the FK is `ON DELETE SET NULL` (almost certainly the reviewer account deleted+recreated 2026-06-11). The Fold 7 tester is a member of that clique; other test accounts aren't, hence the false device-correlation. Two layered defects:
1. `CliqueModel.fromJson` cast `json['created_by_user_id'] as String` (non-null) → threw `type 'Null' is not a subtype of type 'String' in type cast`, erroring the cliques provider.
2. `home_screen.dart` read `cliquesAsync.value`, and **`AsyncValue.value` rethrows on an error state** → the rethrow crashed the whole Home `build()` → grey box.

**Blast radius.** The same non-null cast existed in **four models** — `clique_model`, `event_model`, `photo_model`, `video_model` (`created_by_user_id`/`uploaded_by_user_id`). Because account deletion nulls all those FKs, **any** user deleting their account would have crashed the app for every co-member viewing that clique's cliques/events/photos/videos. Pre-release landmine, not a one-off.

**Diagnosis method.** The app had **no global error handling**, so the release `RenderErrorBox` rendered silently and nothing was logged; the tester couldn't capture logcat. Added a temporary on-device error boundary (`FlutterError.onError` + a trivial `ErrorWidget.builder` that prints the exception + stack on the brand dark surface) → the tester screenshotted the exact exception + `home_screen.dart:355` frame. Kept as a **permanent** safety net.

**Fix.**
- 4 models: creator/uploader id now `as String? ?? ''` (`''` is safe — only used in `== currentUserId` ownership checks).
- `home_screen.dart`: `.value` → `.valueOrNull` (no rethrow during build).
- `main.dart`: permanent global error boundary (`FlutterError.onError` + `platformDispatcher.onError` + `ErrorWidget.builder`). Verbosity gated by `_kVerboseErrorScreen` (currently `true` — shows the stack; flip to `false` for a friendly production message once client crash telemetry lands).
- Regression test `app/test/model_null_creator_test.dart` (4 cases).

**Verification.** `flutter analyze` 54-issue baseline preserved · **120/120 tests** (116 + 4 new) · clean release APK built (`flutter clean` + `build apk --release`, 67.9 MB) · **device-confirmed on the Z Fold 7.**

**Follow-ups.** (1) Wire client crash telemetry (`/api/telemetry/error`) then flip `_kVerboseErrorScreen=false` before public release. (2) Decide whether an orphaned-creator clique should reassign ownership to a remaining member (the FK `SET NULL` itself is a legit design choice; clients now tolerate it). (3) Verify the web client tolerates null creators (JS likely doesn't runtime-crash, but confirm).

---

## COST INCIDENT: transcoder job $447 month-to-date — root-caused + mitigated (2026-06-11)

**Status:** ✅ mitigated live (`az containerapp job update --min-executions 0`, verified — execution churn stopped at 2026-06-12T01:31Z) · ✅ docs updated (CLAUDE.md, VIDEO_ARCHITECTURE_DECISIONS.md Decision 12 revision, VIDEO_INFRASTRUCTURE_RUNBOOK.md) · ⏳ **Azure support ticket for the June 3-9 metering anomaly (~$435) — recommended, not yet filed.**

**Discovery.** Billing-account cost analysis showed June forecast $1,613 vs $850 budget. Cost Management breakdown: CLIQUE Pix subscription $543.58 MTD (June 1-11), of which **$447.64 was `caj-cliquepix-transcoder`** (next largest: APIM $53.42). My AI Bartender subscription $147.27; ~$100 more bills at account level outside both subscriptions.

**Two distinct problems:**

1. **Chronic idle burn (~$110-150/month): `minExecutions=1`.** On an Event-triggered Container Apps Job, `minExecutions=1` makes KEDA spawn at least one execution per scaling evaluation **even with an empty queue**. Live behavior (verified in execution history + console logs): a new execution every ~30s, 24/7, ~2,600/day, each logging `[runner] Polling video-transcode-queue... / No messages in queue, exiting cleanly` and exiting in ~1s. Baseline cost ~$3.75/day. This contradicted Decision 12's own "$3-11/month" Jobs estimate (only true at `minExecutions=0`). **Fixed:** `minExecutions=0`; `pollingInterval=5` retained (detection latency unchanged when real messages arrive). Trade-off: first transcode now eats the full ~15-25s cold start — acceptable per Decision 13 (uploader plays locally; cold start only delays other members' view).

2. **June 3-9 metering anomaly (~$435): billed ~14 replica-equivalents 24/7 with provably flat workload.** Cost meters (`Standard vCPU/Memory Active Usage`) jumped $3.74/day → ~$73/day for June 4-8 (ramp started ~June 3 18:00 UTC, decayed June 9-10). Every customer-side signal was flat across the window: execution count (~2,600/day, all `Completed`), container run time (p50 = 1s), pod lifecycle (~180s), image pulls, console+system log volume (~30k rows/day), and exactly ONE real transcode all week (June 6, 41.6s, succeeded — the only video upload in June per `AppEvents`). No config/deploy change aligns with onset or recovery (the only change in the window, transcoder v0.1.8 on June 4 22:02 UTC, sits mid-window with no cost effect either way). Smoking gun: the job's platform metrics (`UsageNanoCores`) **stopped emitting at exactly the cost ramp onset** (June 3 ~18:00 UTC) and stayed dark through the window; the single bucket that emerged (June 6 12-18h) showed 1.03 cores sustained average — unexplainable by the 41s transcode (≈0.004 core-avg for that bucket). Conclusion: platform-side — either orphaned/zombie replicas held provisioned (invisible to customer logs) or a metering error. **The evidence above supports a billing-credit support ticket.**

**Forecast impact:** with the anomaly over and `minExecutions=0`, the transcoder line drops to near-zero; June lands around ~$950-1,000 account-wide (the spike is already booked) and ~$600-650/month run-rate after. Largest remaining structural items: two APIM Basic v2 instances (~$150/mo each across the two subscriptions).

**Also found while investigating:** the `az monitor app-insights query` API against `appi-cliquepix-prod` returned only ~1 hour of data, but ALL telemetry is intact in the underlying Log Analytics workspace `log-cliquepix-prod` (workspace id `c158e174-b84f-41f3-bc36-03fbaf279eb7`; `AppTraces` 2M rows back to May 13). For diagnostics, query the workspace tables (`AppEvents`/`AppTraces`/`AppRequests`, plus `ContainerAppConsoleLogs_CL`/`ContainerAppSystemLogs_CL`) directly via `az monitor log-analytics query`.

**Rollback:** `az containerapp job update -n caj-cliquepix-transcoder -g rg-cliquepix-prod --min-executions 1` (don't — see Decision 12 revision note).

---

## INCIDENT: blank screen after login (paywall lockout) — root-caused + resolved (2026-06-11)

**Status:** ✅ users unblocked (server-side, same day) · ✅ two backend bugs fixed + **deployed** (`func publish`, health 200 direct + Front Door) · ✅ reviewer promotional grant **verified end-to-end** (`entitlement_active=t`, store `PROMOTIONAL`, expires 2101) · ⏳ Flutter fixes on `main`, ship with the **next planned mobile build** (deliberately not interrupting versionCode 7 in Google review).

**The incident.** Every existing user — all 14, including the App Store reviewer account — saw a blank dark-navy screen with only a top-right account icon after sign-in (`problem01.png`). Two compounding causes:

1. **Trial cliff.** Migration 013 (2026-06-02) backfilled `trial_ends_at = NOW() + 7 days` for all existing users → every trial expired 2026-06-09 20:50 UTC. Phase 6 promo grants had not been issued. `effective_active=false` → router hard-redirected everyone to `/paywall`.
2. **Blank Android paywall.** `revenuecat_constants.dart` still has the placeholder `goog_REPLACE_WITH_ANDROID_PUBLIC_KEY`; `Purchases.configure()` failed silently; `PaywallView` (a bare platform view with NO load-failure callback) rendered nothing — leaving just the Scaffold background + AppBar account icon. New users were unaffected (fresh 7-day trial at first sign-in).

**Immediate resolution (no build, live within seconds):**
- `UPDATE users SET trial_ends_at = NOW() + INTERVAL '30 days' WHERE entitlement_active = FALSE AND (trial_ends_at IS NULL OR trial_ends_at < NOW() + INTERVAL '30 days')` on `pg-cliquepixdb` → **14 rows**, all now `2026-07-11 20:02 UTC`; verified 0 locked-out users remain. (`effective_active` is computed live per request — no caching, no deploy needed.) Note: the `AllowDevMachine` DB firewall rule was updated to the dev box's new IP (38.125.100.43 → 38.125.100.58).
- Reviewer `vwhitley1967@gmail.com` (`325e4455-…`) granted RevenueCat **promotional lifetime** `plus` (expires 2101-01-01) — the GENE.md Phase 6 mechanism — and verified all the way into Postgres. **Superseded later the same day:** the reviewer account turned out to be an OTP-era Entra account (created hours before the 2026-05-06 password-flow switch, so it emailed sign-in codes — unusable for App Review). It was deleted (in-app + Entra) and re-created under the password flow → new `users.id a16a8a7c-74ca-4efc-9460-27c08db4061e`, lifetime grant **re-issued + verified** (`entitlement_active=t`, `PROMOTIONAL`, expires 2100 — webhook flowed instantly through the fixed resolution).

**Production backend bugs found during the grant verification (both fixed + deployed 2026-06-11):**

| Bug | Symptom | Fix |
|---|---|---|
| **Webhook `app_user_id` resolution order** (`entitlementService.ts`) | `upsertEntitlement` preferred `original_app_user_id` — which RC pins to the customer's FIRST id, i.e. `$RCAnonymousID:…` **forever** for SDK-created customers — so EVERY webhook for an anonymous-origin customer failed the UUID guard and was dropped as `invalid_user_id`. Confirmed in App Insights: the reviewer's grant arrived (`entitlement_webhook_received`, valid UUID in `app_user_id`) and was skipped. Store purchases self-healed only via the client's 30s REST force-sync; dashboard promo grants and server-driven renewals/expirations were silently lost. | Resolve the FIRST valid-UUID among `app_user_id` → `original_app_user_id` → `aliases[]`. Regression tests added (`entitlementHardening.test.ts`). |
| **RC REST client on API v1 with a v2-only key** (`revenuecatRestClient.ts`) | The Key Vault secret `revenuecat-secret-api-key` is a **v2 project key**; RC v1 endpoints reject it with error 7723 (verified live). So `forceSyncFromRcApi` (Profile "Refresh Subscription" + 30s post-purchase recovery) and `deleteSubscriberFromRc` (GDPR delete) **failed on every production call since paywall launch** — invisibly, because both are best-effort and swallow errors. | Client rewritten against **API v2** (`/v2/projects/{p}/customers/{id}/subscriptions` filtered on `gives_access` + entitlement `lookup_key='plus'`; customer DELETE for GDPR). Response shapes verified live before the rewrite. `forceSyncFromRcApi` adapted; lag-guard tests updated. |

Backend verification: `tsc` clean, **223/223 jest**, deployed via `func publish`, `/api/health` 200 (direct + `api.clique-pix.com`), and the re-granted reviewer entitlement flowed RC → webhook → fixed resolution → `entitlement_active=TRUE` in Postgres.

**Flutter fixes on `main` (ship with next build):**
- **Paywall never-blank hardening:** new `paywallOfferingProvider` pre-flight (configure → `isConfigured` → `getOfferings()` with 10s timeout → require a current offering with packages) gates `PaywallView`; failures render a branded fallback (Try Again / **Refresh subscription status** — the escape path for server-side promo grants / Manage account). `RevenueCatService.configure()` is now observable (`isConfigured`, `configureError`, telemetry `revenuecat_configure_failed`) and short-circuits placeholder keys. New telemetry: `paywall_offerings_load_failed`, `paywall_fallback_shown`.
- **Stable-router fix:** `routerProvider` previously `ref.watch`ed auth state, so **every** benign AuthAuthenticated re-assignment (background verify, avatar update, each post-purchase `refreshEntitlement`) recreated the GoRouter and **reset navigation to `/events`** — verified empirically in `test/router_recreation_behavior_test.dart` (go_router 14.8.1). Now: router created once per signed-in identity (`currentUserIdProvider` watch keeps the cross-user tab-stack reset), redirect re-evaluation via `refreshListenable`. `DeepLinkService` takes a router *getter* (a captured instance went stale on recreation — warm deep links after auth churn routed on a detached router).
- **Paywall allowlist gaps:** `/invite/*` and `/diagnostics` now exempt from the paywall redirect (a lapsed user tapping an invite link silently lost the invite code; Token Diagnostics was unreachable exactly when locked out). Closes the security-audit "Remaining" item.
- **402 handling (was: none):** `AuthInterceptor` fires a throttled (60s) `refreshEntitlement()` on `SUBSCRIPTION_REQUIRED` so the paywall gate engages promptly for stale-cached users; `friendlyApiErrorMessage` maps 402.
- Dead code removed: `RevenueCatService.presentPaywall()` (PaywallView is the mechanism).

Flutter verification: `flutter analyze` 54-issue baseline preserved · **116/116 tests** (96 baseline + new paywall pre-flight, fallback-widget, router-behavior, and constants tests).

**Remaining / follow-ups:**
- Ship the next mobile build (carries all pending Flutter fixes: this incident's hardening + #24/#25 + photo-quality 3024/q88).
- Beta-tester promo grants (GENE.md Phase 6): reviewer DONE; the 4 testers still need grants once Gene picks them — the 30-day trial covers everyone until 2026-07-11. Android-only testers have no RC customer yet (placeholder key blocks `Purchases.logIn`); grant after the Android RC key ships, or rely on the trial.
- The real Android fix remains Play billing + the `goog_` SDK key (GENE.md Phase 1b/1c).

**Rollback:** SQL is data-only (re-shrink `trial_ends_at` to revert). Backend: `git revert` + `func publish` (no migration). Flutter: not yet shipped.

---

## Play rejection fix — READ_MEDIA_IMAGES / READ_MEDIA_VIDEO removed (2026-06-10)

**Status:** ✅ code fixed + AAB rebuilt (versionCode **7**, PR #52); ✅ uploaded to Play Console 2026-06-10; ⏳ **in Google review** (policy resubmissions typically clear in 24–48h).

**What happened.** Google Play **rejected** the versionCode 6 AAB (the 2026-06-09 brand-rename build) under the **Photo and Video Permissions policy** ("Permission use is not directly related to your app's core purpose", flagged area "Policy Declaration for Photo Picker"). `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` are reserved for apps whose core purpose requires persistent broad gallery access; apps with one-time/infrequent access must use the Android Photo Picker.

**Root cause.** Both permissions were declared directly in `app/android/app/src/main/AndroidManifest.xml` (no plugin contributes them — confirmed via the manifest-merger blame report) and were **entirely unused**: `image_picker` 1.2.1 picks media via the permission-free backported Photo Picker, `gal` 2.3.2 saves via MediaStore (permission-free on API 29+; legacy `WRITE_EXTERNAL_STORAGE maxSdkVersion=29` already declared), and no code path requests them via `permission_handler`. Removing them changes zero runtime behavior.

**Fix.**
- Manifest: both permissions replaced with `tools:node="remove"` pins (same guard pattern as the exact-alarm suppression) so no future plugin can re-introduce them in the merge. `READ_EXTERNAL_STORAGE maxSdkVersion=32` / `WRITE_EXTERNAL_STORAGE maxSdkVersion=29` kept (not policy-flagged; auto-ignored on Android 13+).
- `app/pubspec.yaml`: `1.0.0+6` → `1.0.0+7` (rejected version codes can't be resubmitted).
- New don't-regress invariant recorded in `HANDOFF.md §6` + `.claude/CLAUDE.md`.
- `flutter clean` → `flutter build appbundle --release`; merged manifest verified clean of both permissions, `versionCode="7"`.

**Gene's manual Play Console steps:**
1. Upload the new versionCode 7 AAB to the same track ("Send for review").
2. Google requires removal "from all version codes within the submission, **including testing tracks**" — supersede/pause any active testing-track releases still carrying versionCode ≤ 6.
3. **App content → Photos and videos permissions** declaration: update/confirm the app does not use these permissions.

---

## Brand rename "Clique Pix" → "CLIQUE Pix" (2026-06-09)

**Status:** ✅ rolled out across all code channels **and** the RevenueCat paywall; manual store/console/design items remain (tracked in `docs/GENE.md`). The user-facing wordmark was capitalized to **CLIQUE Pix** (whole word CLIQUE) in **PR #47** — a fixed-string swap of the literal "Clique Pix" across **264 occurrences / 67 tracked files**. The two-word brand phrase only; identifiers (`cliquepix`/`clique_pix`/`clique-pix.com`/`com.cliquepix.*`/`CFBundleName`/FCM channel ID) and the feature noun "Clique"/"Cliques" deliberately untouched. Build number bumped `1.0.0+5 → +6` (**PR #46**) for the upcoming store upload.

| Surface | Change | Deploy channel | Live? |
|---|---|---|---|
| **Web** | landing/nav/footer, `index.html` title/OG/twitter, legal `privacy.html` + `terms.html` | SWA auto-deploy on merge | ✅ **live** — verified "CLIQUE Pix" at `clique-pix.com` + `/docs/privacy` + `/docs/terms` |
| **Backend** | 2 user-facing error strings (age-gate + subscription-required) | `func azure functionapp publish func-cliquepix-fresh` (2026-06-09) | ✅ **live** — `/api/health` 200 |
| **Android** | in-app copy + `android:label="CLIQUE Pix"` | versionCode 6 AAB **rejected by Play 2026-06-10** (media-permissions policy — see entry above); superseded by versionCode 7 AAB rebuilt 2026-06-10 at `app/build/app/outputs/bundle/release/app-release.aab` | ⏳ **+7 uploaded 2026-06-10 — in Google review** |
| **iOS** | in-app copy + `CFBundleDisplayName="CLIQUE Pix"` | `flutter build ipa` from the Mac | ✅ **done** — superseded by the `1.0.0 (9)` production IPA uploaded 2026-06-18 (in Apple review; adds the branded launch screen — see top entry). Prior: Gene confirmed 2026-06-10 an IPA showing "CLIQUE Pix" (post-#47 `main`, carries #24/#25). |
| **RevenueCat paywall** | headline "Subscribe to CLIQUE Pix" + monthly/annual plan labels | RC Paywall AI Editor draft (assistant, verified) → **Gene published** | ✅ **live 2026-06-09** — Gene confirmed "Subscribe to CLIQUE Pix" + hit Publish |

**Docs/memory:** `.claude/CLAUDE.md` + ~24 `/docs` files swept in #47; `HANDOFF.md` gained the iOS `.ipa` build path + GitHub Actions secrets table (#45/#48); `GENE.md` gained the rename follow-up checklist + paywall status (#49/#50); `feedback_app_name.md` memory updated to the new convention.

**Manual/external still pending (Gene — no code; tracked in `docs/GENE.md`):** App Store Connect + Play Console app/listing names → "CLIQUE Pix"; subscription group/product display names; Entra app-registration display name + Google OAuth consent-screen name (the app name shown during auth); and the logo/icon/splash/store-screenshot **image assets** (wordmark rendered as pixels — design work).

---

## Post-audit hardening cluster #24–#28 + SWA cleanup (2026-06-05)

**Status:** mixed by channel (see table). The pre-submission audit (#17) surfaced follow-ups that landed as #24–#27; #28 is unrelated CI maintenance.

| PR | Area | Change | Deploy channel | Live? |
|---|---|---|---|---|
| **#24** | Flutter | briefError launch-crash RangeError (bounded by full multi-line length, applied to first line) fixed; 9 bootstrap screens swapped error.toString()→friendlyApiErrorMessage; gallery-save temp-file leaks plugged; FCM token fragment removed from debugPrint | next Play/TestFlight build | ⏳ app build pending |
| **#25** | Flutter | 5-layer-defense hardening: _authEpoch session-resurrection guard, 401 retry-loop guard, single-flight refresh mutex, optimistic-entitlement reset on identity change | next Play/TestFlight build | ⏳ app build pending |
| **#26** | Webapp | DM sender-identity uses cached verified-user UUID; EntitlementGuard recoverable error state (no more permanent blank screen on non-401 /auth/verify failure); Lightbox downloads playable MP4 fallback for videos | SWA auto-deploy on merge | ✅ live (verify at clique-pix.com) |
| **#27** | Webapp | web DM mark-read sends last_read_message_id (backend 400'd without it) | SWA auto-deploy on merge | ✅ live (verify at clique-pix.com) |
| **#28** | CI | actions/checkout & actions/setup-node @v4 → @v6 (Node 24, ahead of GitHub's 2026-06-16 Node-20 cutoff) across all 4 workflows; dropped dead eslint-disable in webapp videoUpload.ts | merge to main | ✅ live (all workflows on @v6) |

**SWA staging-env auto-cleanup fix (added this change set).** The Azure SWA PR-close cleanup job never ran: it lived in `webapp-deploy.yml` whose `pull_request` trigger has a `paths:` filter but no `types:`, defaulting to [opened, synchronize, reopened] — `closed` was never delivered, so the close job had 0 executions across ~30 PRs and staging envs orphaned until the Free-tier 3-env cap blocked the next deploy (the same orphan-env problem noted under the 2026-06-04 Ops line). Fix: a dedicated `.github/workflows/swa-cleanup.yml` workflow now triggers on `pull_request: types: [closed]` with NO paths filter; the dead `close_pull_request` job is removed from `webapp-deploy.yml` and its build_and_deploy `if` simplified. Both the new workflow and the deploy action are pinned to the immutable SHA `1a947af9992250f3bc2e68ad0754c0b0c11566c9` (v1) for supply-chain hardening. The new workflow only takes effect for PRs closed after it lands on `main` (it can't clean up a PR closed before it exists).

**Deploy note:** #26/#27 are already live via SWA auto-deploy. #24/#25 require a new mobile build. **#22 + #23 backend fixes deployed 2026-06-05** via `func azure functionapp publish func-cliquepix-fresh` — `GET /api/health` → 200, and the hardened RevenueCat webhook now returns `401 UNAUTHORIZED` ("Webhook authentication failed") on an unauthenticated call, confirming the #22 `revenuecatAuthMiddleware` change is live in prod.

---

## Re-audit follow-up — ship-blocker fixes deployed (2026-06-04)

**Status:** ✅ deployed & verified (backend + transcoder + assetlinks). An independent re-audit (13 finders × adversarial verification; 89 raw → 69 confirmed; full machine-readable set in workflow run `wf_1616060a-dc4`) re-checked the audit fixes above and surfaced **4 ship-blockers — including a regression introduced by the C1 fix**. All four are on `main` (PRs **#18** assetlinks, **#19** backend/transcoder/app). Canonical findings record: `docs/SECURITY_AUDIT_2026-06-04.md` → "Follow-up re-audit".

| ID | Fix | Deploy channel | Live? |
|---|---|---|---|
| **INV-1** | `joinClique` validated `invite_code` with maxLength 20 — truncating the C1 32-char codes — so the exact-match lookup 404'd; **every clique created since C1 was un-joinable** (link/QR/SMS/web). Now `INVITE_CODE_MAX_LENGTH=64` coupled to the generator + `inviteCode.test.ts` round-trip. | `func azure functionapp publish func-cliquepix-fresh` | ✅ **live** — `/api/health` 200 (direct + Front Door) |
| **BLOB-1** | sole-owner `leaveClique` CASCADE-dropped media rows but never deleted blobs (C2 `deleteMediaAssets` not wired here) → now enumerates clique media and deletes blobs before `DELETE FROM cliques`. | same backend publish | ✅ **live** |
| **TQ-1** | bare `@azure/storage-queue` SDK has **no** auto-DLQ (that's a Functions trigger feature) → a failing callback / malformed message respawned a 2-vCPU replica forever. Adds `MAX_DEQUEUE_COUNT` poison guard + terminal callback + malformed-message drop on dequeue. | transcoder **v0.1.8** (retagged from CI build `acf108d…` via `az acr import`) + `az containerapp job update` | ✅ **live** next transcode (job verified on `:v0.1.8`) |
| **AUTH-1** | msauth redirect hash was the **debug** keystore cert → sign-in fails on Play-signed builds. `androidRedirectUri` now `String.fromEnvironment` defaulting to the **release** hash (`4FsaiJ4wJWgM09R/hUh3osYJhgg=`); both `<data>` paths in the manifest; debug opts in via `dart_defines/debug.json`. | Entra redirect registered (portal) ✅; **app side ships in next Play-signed build** | ⏳ app side pending build |
| **H4** | assetlinks carried only the debug SHA-256 → added the release Play App Signing SHA-256 (`BD:B3:DE:EC:…:60:75:FB`). | SWA (PR #18) | ✅ **live** — served at `clique-pix.com/.well-known/assetlinks.json` |

**Backend deploy:** `npm run build` clean + 185/185 jest (was 181 — +4 invite-code regression tests); `func azure functionapp publish func-cliquepix-fresh` succeeded; `GET /api/health` → **200** on `func-cliquepix-fresh.azurewebsites.net` AND `api.clique-pix.com`.

**Transcoder deploy:** `az acr import` retagged CI image `cliquepix-transcoder:acf108d3a29f52813bd628bdc4de62cce923d591` → `:v0.1.8`; `az containerapp job update -n caj-cliquepix-transcoder -g rg-cliquepix-prod --image …:v0.1.8`; job image **verified** `:v0.1.8`. Corrected the false "Storage Queue has built-in DLQ after 5 dequeues" claim in `VIDEO_ARCHITECTURE_DECISIONS.md`.

**Ops:** deleted 3 orphaned SWA staging environments (PRs 13/15/17) that were maxing the Free-tier cap and failing PR previews; production `default` env untouched.

**Follow-on hardening (the original 7 high/medium follow-ups):** ✅ **reviewer-lockout** `expires_date:null` promo grants (PR #21 — merged + **deployed**, health 200). ✅ **RC webhook 500 retry-storm** + non-UUID guard + missing-secret-now-401, ✅ **`markExpired` TOCTOU** (PR #22 — merged + **deployed 2026-06-05**). ✅ **NOTIF-1** in-app notifications for web-only users, ✅ **NOTIF-2** FCM transient-failure token purge, ✅ **TQ-2** event-expiry vs in-flight transcode race (PR #23 — merged + **deployed 2026-06-05**). The `_briefError` startup `RangeError` flagged here was fixed in PR #24 (merged 2026-06-05) and ships in the next app build — see the 2026-06-05 entry below. PR #22 + #23 shipped together in the 2026-06-05 backend `func publish` (`/api/health` 200; webhook auth 401 probe confirmed). Details + residual follow-ups in `docs/SECURITY_AUDIT_2026-06-04.md`.

---

## Pre-submission security & detrimental-bug audit (2026-06-04)

**Status:** ✅ code complete on branch `security/audit-fixes-2026-06-04` (4 commits), ✅ backend 181/181 jest (was 174 — +7 new regression tests) + tsc clean, ✅ Flutter `analyze` 54-issue baseline preserved + 96/96 tests, ✅ webapp lint clean + build green. **Pending:** branch review/merge to `main`, backend `func publish` + mobile/web ship, and the Gene-applied config item (H4 assetlinks). **Not yet deployed.**

**Why now.** RevenueCat paywall went live in prod 2026-06-02 and App Store submission is days away. Gene asked for a deep audit for "anything detrimental — above all, major security holes" before real subscribers arrive. Full methodology, every finding (Critical→Low), the verified-clean list, and the don't-regress invariants are in **`docs/SECURITY_AUDIT_2026-06-04.md`** — that is the canonical record; this entry is the deploy-tracking summary.

**Headline:** no remote, unauthenticated data-breach-class hole. Fundamentals verified sound (parameterized SQL, `execFile` ffmpeg, blob-scoped SAS, JWT validation, constant-time webhook compare, no committed secrets, no token/PII logging). Six adversarial audit dimensions; every Critical/High independently re-verified against source.

**What shipped (4 commits):**

| Commit | IDs | Change |
|---|---|---|
| `85116d2` | C1, H5, L1 | Invite codes 32-bit → 128-bit (`crypto.randomBytes(16)`); `npm audit fix` cleared HIGH axios (webapp) + fast-xml-builder (backend/transcoder); avatar snooze SQL → `make_interval(days => $2)` |
| `7e2dd75` | C2 | New `blobService.deleteMediaAssets` wired into `deleteEvent`, `deleteMe` (×2), and the expiry timer safety-net so video HLS/fallback/poster blobs are actually deleted (+4 regression tests) |
| `b40e978` | H1, H2 | `forceSyncFromRcApi` no longer locks out a just-paid subscriber off a stale RC API read (+3 tests); atomic `status='pending'` claim closes the orphan-cleanup vs upload-confirm race on both sides |
| `ae37344` | H6, H3 | `DELETE /api/push-tokens` + Flutter `deregister()` wired into sign-out/delete before the JWT clears; corrected the false "managed-identity" transcoder-callback claim (it's an Azure Functions function key) in CLAUDE.md + ARCHITECTURE.md |

**New telemetry events:** `photo_commit_lost_to_orphan_cleanup`, `video_commit_lost_to_orphan_cleanup` (upload reaped mid-confirm — should be rare; a spike means the orphan windows are too tight), `entitlement_force_sync_skipped_api_lag` (H1 guard fired — confirms the lockout path is being avoided).

**Deploy order when merged:** backend `func azure functionapp publish func-cliquepix-fresh` (additive — new DELETE endpoint, old clients unaffected) → webapp auto-deploy on merge (axios bump) → mobile build (FCM de-register + version bump). No DB migration. No infra change.

**Left for Gene (config, not code):**
- **H4 (before Android production):** `webapp/public/.well-known/assetlinks.json` carries the **debug** keystore SHA256 — replace with the release upload-key + Play App Signing fingerprints and redeploy SWA, else App Links break on Play-signed installs and are sideload-spoofable.
- Medium/Low items (403-vs-404 oracles, `entitlement/refresh` distributed throttle, paywall-allowlist `/invite`+`/diagnostics`, open-redirect param validation, webapp test gap) tracked in `docs/SECURITY_AUDIT_2026-06-04.md` "Remaining."

**Trial farming** (delete account → re-signup = fresh 7-day trial) was adjudicated **accepted-by-design** for a no-card trial — documented, not fixed.

**Rollback:** the branch is unmerged; if merged, each fix is an independent commit with no migration/infra. `git revert <sha>` restores prior behavior (re-introducing the corresponding finding).

---

## Install-aware QR invites — Phase A/B/C-interim shipped (2026-05-13)

**Status:** ✅ code complete (2 commits, 18 files touched), ✅ pushed to `origin/main` (commits `56ae257` + `0103c87`), ✅ release AAB built (`app-release.aab`, 52.1 MB, versionCode=4, versionName=1.0.0), ✅ packaged manifest verified (`versionCode="4"`, `versionName="1.0.0"`). **Pending:** manual upload of new AAB to Play Console Open Testing; webapp SWA deploy GitHub Actions workflow auto-triggers from the push and rolls Phase A + C-interim to production at `clique-pix.com`.

**The user observation that triggered this work.** Person A scans Person B's Clique invite QR on a phone that doesn't have CLIQUE Pix installed today. The web page at `clique-pix.com/invite/{code}` worked for the no-install path (sign in → join via web), but there was no install upsell AND no way to preserve the invite code across an install → first-launch sequence. The user asked: "Could the QR also direct them to install the app AND preserve the invite context?"

**The four-phase design (Phase A + B + C-interim shipped this session; C-final deferred).** Full architecture in `docs/INVITE_INSTALL_REFERRER.md`.

| Phase | Platform | Mechanism | Shipped |
|---|---|---|---|
| **A** | Web | `InstallBanner` on `/invite/{code}` renders platform-appropriate Store badge above the existing sign-in CTA. Benefit bullets ("In-app camera + editor / push notifications / save to camera roll / Full HD video"). Android + Desktop see Google Play badge whose href carries `?referrer=invite_code%3D{code}` URL-encoded. iOS gets a TestFlight badge (see Phase C-interim) | ✅ 2026-05-13 |
| **B** | Android | `play_install_referrer` Flutter package ^0.5.0 reads the Play Install Referrer once per install. New `InstallReferrerService` parses `invite_code=` out of the URL-decoded referrer string and persists to SharedPreferences key `install_referrer_pending_invite_code`. `_CliquePixState` consumes the pending code on `AuthAuthenticated` transition (via post-frame callback for bootstrap-authed users and `ref.listen<AuthState>` for post-sign-in users) and routes to `/invite/{code}` — `JoinCliqueScreen` auto-joins | ✅ 2026-05-13 (effective once AAB versionCode=4 is approved in Play Open Testing) |
| **C-interim** | iOS | New `TestFlightBadge` component (visual chassis matches `AppStoreBadge`, copy "Get it via / TestFlight", Apple icon from `lucide-react`). Banner caption sets the correct expectation: *"iOS is in public beta on TestFlight. After installing, tap your invite link again to join the Clique."* — no Apple equivalent of Play Install Referrer exists, so iOS users retap the invite link from Messages post-install to trigger Universal Link routing | ✅ 2026-05-13 |
| **C-final** | iOS | Smart App Banner meta tag (`<meta name="apple-itunes-app" content="app-id=6766294274, app-argument={current URL}">`) in `webapp/index.html`. Native Safari delivers `app-argument` to the app via `NSUserActivity.webpageURL` after install. Apple ID `6766294274` exists in App Store Connect but no public listing approved yet (verified via `https://itunes.apple.com/lookup?id=6766294274` returning `resultCount: 0`). Activation steps with the concrete Apple ID and copy-paste useEffect snippet documented in `docs/INVITE_INSTALL_REFERRER.md` §"Phase C-final" | ⏳ Gated on App Store listing approval |

**Idempotency invariants for Phase B (critical to get right).**

- **`install_referrer_consumed`** SharedPreferences flag is set after the FIRST read attempt regardless of result. Subsequent cold starts skip the Play API call entirely (saves battery; the Play API is expensive). Self-enforced one-shot semantics.
- **`install_referrer_pending_invite_code`** is cleared as soon as the auth-state listener consumes it. Force-stop + cold-restart after consumption does NOT re-fire the auto-join.
- **`_inviteAutoJoinChecked`** in-memory flag in `_CliquePixState` guards against re-firing within the same process. Reset to `false` when the user transitions OUT of `AuthAuthenticated` (sign-out → sign-in as new user) so a new pending invite can still be consumed by a different user without a process restart.
- **Why SharedPreferences over a Riverpod provider:** the pending code must survive process death between the referrer-read (post-first-frame `performDeferredInit`) and the consume (post-sign-in `AuthAuthenticated`, which may be minutes or days later). A Riverpod provider would be lost on process death; SharedPreferences is the durable primitive.

**Telemetry events added.**

| Event | Properties | Emitter |
|---|---|---|
| `web_invite_install_banner_shown` | `platform: 'android'\|'ios'\|'desktop'` | `webapp/src/features/cliques/InstallBanner.tsx` useEffect |
| `web_invite_install_badge_clicked` | `platform: 'android'\|'ios'` | `InstallBanner.tsx` onClick |
| `web_invite_web_signin_clicked` | — | `InviteAcceptScreen.tsx` onSignIn |
| `install_referrer_read` | `had_invite_code=true\|false` (in `errorCode` slot of the pending-isolate queue format) | `app/lib/services/install_referrer_service.dart` |
| `install_referrer_auto_join_attempted` | — | `_CliquePixState._consumePendingInstallReferrerInvite` |

Success/failure of the actual clique join continues to be tracked by the existing `clique_joined` event in the cliques handler.

**Files touched (18 across 2 commits).**

Commit `56ae257` (Phase A + B + initial Phase C planning, 13 files):
- `webapp/src/lib/platform.ts` (new — UA detection)
- `webapp/src/features/cliques/InstallBanner.tsx` (new — platform-aware install upsell)
- `webapp/src/features/cliques/InviteAcceptScreen.tsx` (compose banner + telemetry)
- `webapp/src/features/landing/components/PlayStoreBadge.tsx` (add optional `onClick`)
- `webapp/src/features/landing/sections/Download.tsx` (live Play Store URL)
- `app/pubspec.yaml` (`play_install_referrer: ^0.5.0`, version `1.0.0+3` → `1.0.0+4`)
- `app/pubspec.lock` (transitive)
- `app/lib/services/install_referrer_service.dart` (new)
- `app/lib/main.dart` (invoke `readAndPersistOnce` in `performDeferredInit`)
- `app/lib/app/app.dart` (`_consumePendingInstallReferrerInvite` + post-frame + `ref.listen<AuthState>`)
- `docs/INVITE_INSTALL_REFERRER.md` (new, 192 lines)
- `docs/BETA_TEST_PLAN.md` (4 new test cases in §2 Cliques)
- `.claude/CLAUDE.md` (Deep Linking flow rewrite + telemetry list + Companion Documents table)

Commit `0103c87` (Phase C-interim TestFlight, 5 files):
- `webapp/src/features/landing/components/TestFlightBadge.tsx` (new)
- `webapp/src/features/cliques/InstallBanner.tsx` (iOS branch renders TestFlightBadge + retap caption)
- `docs/INVITE_INSTALL_REFERRER.md` (+72 lines for Phase C-interim flow + iOS limitations + C-final activation steps with concrete `app-id=6766294274`)
- `docs/BETA_TEST_PLAN.md` (iOS install-aware test case rewritten for TestFlight path)
- `.claude/CLAUDE.md` (Companion Documents row touch-up)

**Build verification.**

| Step | Result |
|---|---|
| `flutter clean` | Per `feedback_always_flutter_clean.md` memory — non-negotiable before every release build |
| `flutter pub get` | Resolved `play_install_referrer ^0.5.0` + transitive deps |
| `flutter build appbundle --release` | ✅ Succeeded in 290.6s |
| Output: `app/build/app/outputs/bundle/release/app-release.aab` | 52.1 MB |
| Packaged manifest check (`aapt dump badging` equivalent via grep) | `versionCode="4"`, `versionName="1.0.0"` confirmed |

**iOS identifiers locked in for Phase C-final activation (single source of truth in `docs/INVITE_INSTALL_REFERRER.md`).**
- Apple ID (numeric): `6766294274`
- Bundle ID: `com.cliquepix.app`
- TestFlight enrollment link: `https://testflight.apple.com/join/hWznNvJ6`
- AASA Team ID: `4ML27KY869`

**What this is NOT.**
- ❌ Not a third-party deferred-deep-link service (no Branch.io, AppsFlyer, or Firebase Dynamic Links — the last was deprecated by Google August 2025 anyway).
- ❌ Not an iOS clipboard hack (Smart App Banner is the native Apple primitive; we don't fight Apple by writing to UIPasteboard from Safari).
- ❌ Not iOS App Clips (separate Xcode target + Apple review — out of scope for v1).
- ❌ Not a backend change. Existing `POST /api/cliques/_/join` serves both Phase A (web) and Phase B (Flutter auto-join). No new endpoints, no schema, no migration.

**Operational lesson.** The "Universal Link same-domain rule" caveat — Apple's `NSUserActivity` Universal Link does NOT fire when navigating WITHIN `clique-pix.com` in Safari — is documented prominently in `docs/INVITE_INSTALL_REFERRER.md`. A future agent tempted to add an "Open in App" hyperlink on the invite page pointing at the same URL would silently break the iOS install path; the doc prohibits this explicitly.

**Pending follow-ups.**
- Upload `app/build/app/outputs/bundle/release/app-release.aab` (versionCode=4) to Play Console Open Testing → release notes drafted → Send for review. Manual user action via Play Console UI; Open Testing approvals typically clear within 24h.
- Verify webapp SWA deploy GitHub Actions workflow auto-triggered from the push and rolled Phase A + C-interim live at `clique-pix.com/invite/{any-code}`.
- Phase E real-world Test Plan dry-run after AAB approval (per `docs/BETA_TEST_PLAN.md §2` — 4 new test cases): Android install-aware end-to-end, iOS TestFlight install-aware, desktop browser, `adb shell am broadcast` referrer simulation.
- Phase C-final activation when Apple approves the public App Store listing — copy-paste the meta tag + useEffect snippet from `docs/INVITE_INSTALL_REFERRER.md` §"Phase C-final". Three-line web edit; no Flutter changes needed (existing Universal Link handler in `AppDelegate.swift` already reads `userActivity.webpageURL`).

**Rollback plan.**
- Web (Phase A + C-interim): `git revert 0103c87 56ae257` → next SWA deploy reverts the invite page to its pre-banner state. Existing "Sign in to accept" web-join path is untouched and continues to work.
- Flutter (Phase B): rollback is automatic — versionCode=4 with the referrer integration is OPT-IN at the install-time level. Existing versionCode=3 users keep the pre-Phase-B behavior; new versionCode=4 installs gain auto-join. To explicitly disable post-deploy, ship a versionCode=5 with `InstallReferrerService.readAndPersistOnce()` no-op'd.

---

## iOS cross-account data leak after sign-out → sign-up — fixed (2026-05-06)

**Status:** ✅ code complete, ✅ `flutter analyze` 54-issue baseline preserved, ✅ `flutter test` 87/87 green (was 82 + 5 new regression tests), ✅ iOS release build green (`Runner.app` 35.3 MB), ✅ **on-device verified on Gene's iPhone (UDID `00008120-001965E014C3601E`, iOS 26.4.2) 2026-05-06** — sign-out → different sign-up correctly shows EMPTY state for the new user; no leakage of the prior user's events / cliques / photos. **Pending:** Android APK release build + Samsung verification, commit + push.

**The user complaint.** On iPhone: User A signed in, created Clique + Event + uploaded a photo, then signed out. A brand-new User B signed up on the SAME device in the SAME app session. User B saw User A's Event in their feed AND could navigate into it AND see User A's photos. **Reproducible only on iOS** in the user's testing — Android did not reproduce. Reported 2026-05-06.

**The real root cause (3 coupled defects, none platform-specific).** The bug is iOS-only in observation but platform-agnostic in principle — verified via grep that there is NO `Platform.isIOS` branch anywhere in the auth/provider/cache layer. Backend was audited end-to-end and found sound (`getPhoto` at `backend/src/functions/photos.ts:478-487` correctly checks membership before signing SAS URLs at line 489; `listAllEvents`, `listPhotos`, `getEvent` all enforce `clique_members.user_id = $authUser.id` membership via INNER JOIN). The leak is **100% client-side state retention**:

1. **`AuthNotifier.signOut()` (`app/lib/features/auth/presentation/auth_providers.dart:226-233`) does NOT call `ref.invalidate()` on any data providers** — only sets `state = AuthUnauthenticated`. `grep -rn "ref.invalidate" app/lib/features/auth/` returned ZERO matches.
2. **`AllEventsNotifier.build()` (and `CliquesListNotifier.build()`) did not depend on auth state** — once built with User A's events, the AsyncNotifier instance retained them across sign-out → sign-in. `eventPhotosProvider`, `eventVideosProvider`, `eventDetailProvider`, `notificationsListProvider`, DM providers, etc. — all `FutureProvider.family` / `StateNotifierProvider.family` without `autoDispose` — survived sign-out with their User-A-keyed state intact.
3. **The stale-while-revalidate bootstrap (`eventsBootstrapProvider`, `cliquesBootstrapProvider`) was set ONCE in `main()` via `ProviderScope.overrides`** with User A's events — `ListCacheService.clearAll()` correctly wiped the on-disk cache file but cannot reset the in-memory override. Even after invalidation, the next `build()` would re-read User A's events from the override.

The "iOS-only" observation is most likely Android-specific timing: Android's process management may dispose providers between the sign-out and sign-up steps in ways iOS doesn't. The fix applies universally.

**The fix (4 changes, all client-side, all in `app/lib/`).** See `~/.claude/plans/okay-here-is-the-cozy-shamir.md` for the full plan.

| Change | File | What |
|---|---|---|
| 1a | `app/lib/features/auth/presentation/auth_providers.dart` | Added `currentUserIdProvider` — derived `Provider<String?>` from `authStateProvider`. Watchers only emit on actual user_id changes (String `==` value equality), avoiding flicker on every background-verify refresh of the same user |
| 1b | `app/lib/app/app.dart` | Added `ref.listen<String?>(currentUserIdProvider, ...)` inside `_CliquePixState.build()` with guard `previous != null && previous != next`. On real identity change, calls `_invalidateUserScopedState(ref)` which invalidates 16 user-scoped providers (events × 3, cliques × 3, photos × 3, videos × 4, notifications × 1, DM × 3, including `mediaSelectionProvider` and `localPendingVideosProvider`) plus `PaintingBinding.instance.imageCache.clear()` for in-memory image bytes |
| 2 | `app/lib/core/cache/list_bootstrap_providers.dart` + `app/lib/main.dart` | Added sibling `bootstrapUserIdProvider` overridden alongside the events + cliques bootstrap providers. Tags the bootstrap with the user_id it was loaded for so consumers can fail-closed |
| 3a | `app/lib/features/events/presentation/events_providers.dart` | `AllEventsNotifier.build()` now `ref.watch(currentUserIdProvider)`, returns `const []` when null, gates the bootstrap on `bootstrapUserId == currentUserId`. If User B signs in mid-session, the User-A-tagged bootstrap is rejected and `listAllEvents()` is called fresh |
| 3b | `app/lib/features/cliques/presentation/cliques_providers.dart` | Same fail-closed pattern in `CliquesListNotifier.build()` |
| 4 | `app/test/events_provider_optimistic_test.dart`, `app/test/cliques_provider_optimistic_test.dart` (new) | 5 new regression tests: cross-account leak path (different user_id rejects bootstrap, fresh fetch made), signed-out empty-state path, same-user bootstrap acceptance |

**Decisions deliberately rejected during planning** (see plan for full rationale):
- ❌ **Pass `Ref` into `AuthNotifier`** — anti-pattern in Riverpod 2.x; chose `ref.listen` from a Consumer widget at the app root, matching the existing pattern at `login_screen.dart:104`
- ❌ **Migrate to `IOSOptions(accessibility: first_unlock_this_device)` on `flutter_secure_storage`** — would orphan EXISTING iOS users' Keychain entries written under the prior default, force-logging them out. Defer.
- ❌ **Disk cache clearing via `flutter_cache_manager`** — would require new direct dep (transitive through `cached_network_image`, which Dart cannot import). With provider invalidation, User B's UI never receives User A's photo IDs, so the disk cache is unreachable in practice.
- ❌ **Migrating data providers to `autoDispose`** — broader UX change (re-fetches on every screen revisit). Outside the security-fix scope.

| Phase | Status |
|---|---|
| Plan written + reviewed (`~/.claude/plans/okay-here-is-the-cozy-shamir.md`) | ✅ |
| 6 code edits (auth_providers, list_bootstrap_providers, main, events_providers, cliques_providers, app) | ✅ |
| 5 regression tests (3 in events, 2 in new cliques file) | ✅ |
| `flutter analyze --no-fatal-infos` — 54-issue baseline preserved | ✅ |
| `flutter test` — 87/87 green (82 baseline + 5 new) | ✅ |
| `flutter clean && flutter pub get && flutter build ios --release --no-codesign` — green, 35.3 MB | ✅ |
| `flutter run --release` deploy on Gene's iPhone (UDID `00008120-001965E014C3601E`, iOS 26.4.2) — Xcode build 27.0s, install + launch 5.0s | ✅ 2026-05-06 |
| **iOS on-device verification — sign in as User A, create event + photo, sign out, sign up as User B → User B sees EMPTY events / cliques** | ✅ Verified 2026-05-06 by Gene Whitley |
| APK release build | ⏳ Pending (needs Android SDK env) |
| Samsung on-device verification — same scenario | ⏳ Pending |
| Same-user re-sign-in regression check (must NOT break Welcome Back) | ⏳ Pending |
| Commit + push to main | ⏳ Pending |

**Telemetry to add post-deploy.** A `signout_state_invalidated` event from `_invalidateUserScopedState` (with prev/next user_id 8-char prefixes) should approximately track `auth_verify_success`. Zero events for 24h would mean the listener isn't firing.

**Rollback plan.** `git revert <sha>` — single commit, client-only, no backend / infra / migration. Pre-existing buggy behavior returns. No data corruption possible (changes only clear in-memory state).

---



## APIM Developer → Basic v2 migration — executed (2026-05-05)

**Status:** ✅ End-to-end complete. `apim-cliquepix-002` (Developer, ~$50/month, no SLA) decommissioned. `apim-cliquepix-003` (Basic v2, $150/month, 99.95% SLA, autoscale 1→10 units, v2 platform) provisioned via Bicep, integrated into Front Door, validated via CORS preflight + canonical 401 envelope, and serving 100% of production traffic. Total wall-clock from Phase A start → Phase H decommission: **~46 minutes**.

**Why now.** Pre-launch hardening for App Store / Play Store submission. Developer tier has no SLA, no Azure Status Page coverage, no autoscale — submitting an app with no-SLA gateway during the 24-48h reviewer-flag-traffic window risks a one-time outage you can't redo. $100/month delta (Basic v2 $150 vs Developer $50) buys: 99.95% SLA, scale 1→10 units in seconds, v2 platform reliability, modern API surface, Azure Status Page coverage.

**Why side-by-side + Front Door cutover (and not in-place upgrade).** Per Microsoft's v2 service tiers FAQ verbatim: *"Currently, there's no automated tooling to migrate an existing API Management instance (in the Consumption, Developer, Basic, Standard, or Premium tier) to a new v2 tier instance. The v2 tiers are currently available for newly created service instances only."* You CAN upgrade Developer ↔ Basic / Standard / Premium (classic), and Basic v2 ↔ Standard v2 (v2). You CANNOT upgrade across the classic↔v2 boundary in place. Backup/restore APIs don't support cross-tier restore. Side-by-side new-deploy + Front Door origin cutover is the only supported path.

**The 8 phases as actually executed.**

| Phase | Action | Duration | Outcome |
|---|---|---|---|
| A | Edit `bicep/apim/main.bicep`: SKU `Developer` → `BasicV2`, name → `apim-cliquepix-003`, remove classic-only `customProperties` (TLS cipher toggles) + `legacyPortalStatus`/`developerPortalStatus`/`releaseChannel`, delete ~240 lines of Echo API scaffolding (1 API + 6 ops + 3 op policies + 4 product apiLinks across two ARM resource types), refactor inline ~80-line policy XML → `loadTextContent('../../apim_policy.xml')` (single source of truth, eliminates the 6-incident-history doc drift permanently), de-`@secure()` the three APIM-export-artifact display-name params + add string defaults | ~10 min | Bicep compiles clean (warnings only), what-if shows the desired side-by-side coexistence pattern (60 Creates on `apim-cliquepix-003`, 20 Ignore on existing resources, 0 Modify, 0 Delete) |
| A.5 | `az bicep build` + `az deployment group what-if` validation BEFORE deploy | ~2 min | Both succeed. What-if archived to `C:\Users\genew\AppData\Local\Temp\apim-migration-20260505-1810\what-if.json` for audit |
| B (first attempt) | `az deployment group create` against the bicep | ~3 min | Service `apim-cliquepix-003` provisioned successfully (BasicV2, capacity 1, eastus, system-assigned MI). cliquepix-v1 API + all 7 operations created. **API-scope policy + several scaffolding resources failed.** Root causes: (1) `apim_policy.xml` line 44 had literal `--protocols` inside an XML comment — XML doesn't allow `--` inside `<!-- ... -->`. (2) BasicV2 rejects `portalsettings/{delegation,signin,signup}` (`MethodNotAllowedInPricingTier`). (3) APIM auto-creates system-product↔system-group links at service creation; redeclaring them in bicep returns `Link already exists between specified Product and Group` (this affected BOTH the `service/products/groups` and the newer `service/products/groupLinks` resource types — 12 resources total). (4) System groups (administrators, developers) reject `groups/users/{N}` membership changes (`System group membership cannot be changed`). (5) The default `master` subscription's scope (full service ID with trailing slash) is rejected with `Subscription scope should be one of /apis, /apis/{apiId}, /products/{productId}` — same for the two product subscriptions whose scope is the full product resource ID rather than the relative `/products/{p}` path |
| B (retry after bicep cleanup) | Fix `apim_policy.xml` line 44 (rephrase `--protocols` literal). Remove from bicep: 3 portalsettings, 6 product/groups, 6 product/groupLinks, 2 groups/users/1, 3 subscriptions (master + two product subs). Re-run what-if (1 Create + 7 Modify + 32 NoChange + 0 Delete). Re-deploy. | ~30 sec deploy | ✅ `provisioningState: Succeeded`. CORS preflight from `https://clique-pix.com` returns HTTP 200 with `Access-Control-Allow-Origin: https://clique-pix.com` + identical headers to the old APIM. Direct probe `https://apim-cliquepix-003.azure-api.net/api/health` returns HTTP 200 in ~285ms |
| ~~C~~ | ~~RBAC re-grants for new MI~~ | n/a | **SKIPPED** — pre-flight audit confirmed the old APIM's MI had zero role assignments (no Key Vault refs, no Storage roles), so the new MI doesn't need any either |
| D | `az afd origin create` to add `apim-003-origin` to `apim-origin-group`. **Front Door rejected `--weight 0`** (`Invalid format: '0' is less than 1`). Pivoted to **priority-based routing**: new origin at priority=2 (failover-only), old origin stays priority=1. Front Door only sends traffic to lower-priority origins if all higher-priority origins are unhealthy → new origin gets exactly zero customer traffic during the soak | ~3 min add + ~2.5 min health-probe convergence wait | New origin Enabled, healthy. Front Door continues 100% routing to priority-1 (old APIM). 5/5 health probes return HTTP 200 |
| E | Cutover via priority swap: promote `apim-003-origin` → priority=1 (active), demote `apim-origin` → priority=2 (drained, failover-only). Wait 5 min for Front Door global propagation | ~5.5 min | Front Door now routes 100% of customer traffic to apim-cliquepix-003 Basic v2. CORS preflight + canonical 401 `UNAUTHORIZED` envelope both verified through `api.clique-pix.com`. Latency 213-338ms (comparable to pre-migration) |
| F | End-to-end mobile + web smoke test | (user-driven) | ✅ User reported "looks like things are working" |
| ~~G~~ | ~~24-48h soak~~ | n/a | **COMPRESSED** to inline validation per user direction. The user wanted to stop paying for the Developer instance immediately after Phase F validation passed. Acceptable risk given the cutover already proved end-to-end correctness |
| H | Decommission. Remove `apim-origin` from Front Door origin group (was already drained, zero traffic). Then `az apim delete -n apim-cliquepix-002 --no-wait` + poll until ResourceNotFound | ~2 min total | ✅ apim-cliquepix-002 GONE in 2 polls (~120 sec). Front Door origin group has 1 origin remaining (apim-003-origin priority=1 weight=1000). Final smoke through `api.clique-pix.com/api/health` returns HTTP 200 in 330ms. Developer-tier $50/month meter stopped |

**Audit deltas vs. the §8 runbook draft.** The pre-migration `BETA_OPERATIONS_RUNBOOK.md §8` draft anticipated several things that turned out to be no-ops or wrong:

- **§8 said "RBAC re-grants required for new MI" — actual: zero re-grants needed** (old MI had zero role assignments).
- **§8 said "verify named values for Key Vault refs" — actual: zero named values defined**.
- **§8 said "custom-domain certificates may need migration" — actual: APIM had no custom domain** (Front Door fronts everything).
- **§8 said "remove classic-only properties (vague)" — actual hard ARM blockers** were specifically `customProperties` + `legacyPortalStatus`/`developerPortalStatus`/`releaseChannel` (4 properties); plus a SECOND wave (5 categories of resources) that ARM accepted at first but APIM rejected at the resource level (portalsettings, product/groups, product/groupLinks, groups/users for system groups, subscriptions with bad scope).
- **§8 said "Echo API removal as separate cleanup PR" — actual: removed in this migration**, ~240 lines saved.
- **NEW finding §8 didn't anticipate**: the inline API-scope policy XML in bicep had drifted from `apim_policy.xml` (incident-history comment was 2 incidents stale). Consolidated via `loadTextContent` so the drift can never happen again — the very thing incident #6 lesson #2 already called for.
- **NEW finding §8 didn't anticipate**: Front Door minimum origin weight is 1, not 0. Plan adapted to priority-based routing on the fly.
- **Pricing reality:** $150/month Basic v2 (confirmed by user via Azure pricing calculator pre-flight) — much cheaper than the §8 draft's recollected ~$525/month, which turned out to be Standard v2.

**Outstanding follow-ups (separate work after the migration soaks):**

- **Add APIM-level App Insights logger** — opt-in via separate bicep PR. Currently APIM mgmt-plane logs don't flow to App Insights; Function App's instrumentation does all the work, which is sufficient for now.
- **Pin API version to GA `2024-05-01`** — current bicep uses `2025-03-01-preview`. Preview versions can deprecate without notice; GA is the resilience cleanup.
- **Clean up the 21 `dependsOn` linter warnings** in `bicep/apim/main.bicep` — non-blocking; bicep lint says they're inferable from `parent:` references.
- **Clean up the 2 `no-unused-params` warnings** for `subscriptions_69c2f544f2ccf70039070001_displayName` + `_002_displayName` — they were only used by the now-removed product-subscription resources.
- **Rename bicep symbol `service_apim_cliquepix_002_name_*` to `..._003_name_*`** — currently the symbol names retain "_002_" for minimum diff. Cosmetic refactor, can be a sweep.

**Rollback (no longer relevant — Developer instance is gone).** During Phases B-G the rollback was a 5-min Front Door priority swap reversed. After Phase H decommission the path forward is fix-forward only (per D8 decision).

---

## Cliques tab — labeled "Create Clique" gradient pill replaces bare `+` IconButton (2026-05-05, earlier in the day)

**Status:** ✅ code complete, ✅ `flutter analyze` 54-issue baseline preserved, ✅ `flutter test` 82/82 green, ✅ `flutter clean && flutter pub get && flutter build apk --release` green (`app-release.apk`, 63.0 MB). **Pending:** on-device verification on Samsung + iPhone, commit + push.

**The user complaint.** Earlier in the same session, a `+` IconButton was added to the Cliques tab AppBar (`cliques_list_screen.dart:49-53`, commit `60f1c21`) so users with existing cliques could create another without going through the event-creation flow. User reported back: *"I'm not sure people are going to see the `+` and realize what it's for."* The bare-icon affordance is too subtle for the primary "create" CTA on a tab root.

**The fix.** Mirror the Home tab's existing `_buildCreateEventCTA` gradient pill pattern (`home_screen.dart:628-661`) on the Cliques tab. Same visual treatment as the "Start Another Event" button in `event07.png`:
- Full-width 54 px tall pill, 14 px corner radius
- Primary brand gradient (`AppGradients.primary`: #00C2D1 → #2563EB → #7C3AED)
- Deep-blue drop shadow (α=0.4, blur 20, offset (0, 8))
- White bold text "Create Clique" (17 sp, w700)
- Tap → `context.go('/cliques/create')` (same destination as the prior `+` icon and the empty-state button)

Placed via `SliverMainAxisGroup` ABOVE the first clique card with 12 px top + 16 px bottom margin. Top placement (rather than the bottom placement shown in `event07.png` for Home's "has active events" state) was chosen because Cliques has only one list section — a CTA below a scrollable list is functionally invisible until users scroll, defeating the discoverability goal.

The `+` IconButton is removed from the AppBar entirely. The Refresh icon stays as the sole AppBar action. The empty-state's existing "Create Clique" button (`EmptyStateWidget` in `cliques_list_screen.dart:78-83`) is unchanged — first-time users keep their large prominent CTA, returning users get the gradient pill.

| Phase | Status | Files |
|---|---|---|
| Single-file edit: remove `+` IconButton from AppBar, add `app_gradients.dart` import, wrap non-empty data branch in `SliverMainAxisGroup`, add `_buildCreateCliqueCta(context)` helper at file bottom (verbatim mirror of `_buildCreateEventCTA` except label + route) | ✅ | `app/lib/features/cliques/presentation/cliques_list_screen.dart` (~+40/-5 lines) |
| `flutter analyze` 54-issue baseline | ✅ | — |
| `flutter test` 82/82 green | ✅ | — |
| `flutter clean && flutter pub get && flutter build apk --release` | ✅ Built 2026-05-05 | `app/build/app/outputs/flutter-apk/app-release.apk` (63.0 MB) |
| Docs: this entry + `DEPLOYMENT_STATUS.md` line 761 wording fix + `BETA_TEST_PLAN.md` §2 Cliques smoke-test row | ✅ | as listed |
| On-device verification (Samsung + iPhone — non-empty list shows gradient pill, AppBar shows only Refresh, empty list still shows EmptyStateWidget action button) | ⏳ Pending | — |
| Commit + push to `main` | ⏳ Pending | — |

**Why a gradient pill rather than restoring the historical FAB.** `DEPLOYMENT_STATUS.md:761` describes the original Cliques feature as shipping with a "labeled 'Create Clique' FAB," removed at some point in favor of the bare `+` (which itself caused the discoverability complaint). Going back to a FAB would have worked, but the gradient pill matches today's brand language across Home (three call sites of `_buildCreateEventCTA`) and avoids covering the bottom-most clique card with a floating button. Single canonical pattern beats two parallel "create CTA" patterns across tabs.

**Out of scope (tracked for future):**
- Hoisting `_buildCreateEventCTA` / `_buildCreateCliqueCta` into a shared widget (e.g., `BrandPillButton(label, onTap)` in `app/lib/widgets/`) — currently they're duplicated as private helpers in their respective screens. Worth doing if a third tab adopts the pattern; not worth the abstraction tax for two call sites
- Web parity — `webapp/src/features/cliques/CliquesScreen.tsx` may have its own discoverability gap; separate audit

**Rollback plan.** `git revert <sha>` — single-file change, no backend, no infra, no schema, no new dependency. Pre-existing AppBar `+` returns; users with existing cliques rediscover the regression.

---



## Sign-in 429 from orphaned operation-scope APIM rate-limits — incident #6 — fixed (2026-05-05)

**Status:** ✅ `bicep/apim/main.bicep` edited (6 `apis/operations/policies` resources removed, replaced with explanatory comment block at lines 1247-1260), ✅ live APIM cleaned via 6 `az rest DELETE` calls, ✅ counter cache flushed (`sleep 90 + az apim api update --protocols https`), ✅ on-device verified — sign-in lands on Events screen, no banner. ✅ Diagnostic instrumentation `[AUTH-SIGNIN-FAIL]` debugPrint at `auth_providers.dart:174-180` STAYS as permanent diagnostic. **Pending:** commit + push (this incident's edits to bicep/apim/main.bicep + apim_policy.xml + auth_providers.dart + DEPLOYMENT_STATUS.md + BETA_OPERATIONS_RUNBOOK.md + ARCHITECTURE.md).

**The user complaint.** After rebuilding the release APK in this session for an unrelated cliques-screen UI change, sign-in stopped working on Android. Red banner *"Sign in failed. Please try again."* on the LoginScreen. The cliques-screen change was a 5-line addition in `app/lib/features/cliques/presentation/cliques_list_screen.dart` (a screen rendered only post-auth) — confirmed innocent by `git diff HEAD --stat`. So the rebuild was the trigger but not the cause; something else became visible.

**Why we were initially blind.** The "Sign in failed. Please try again." string at `auth_providers.dart:199` is a generic catch-all. The catch block at lines 174-200 differentiates four cases (age-gate 403, MSAL/AADSTS, TimeoutException, generic) but **does not log the underlying exception** — `final msg = e.toString()` is computed but never printed. Whatever exception fired after MSAL succeeded was being silently swallowed. Three escalating diagnostic steps:

1. **`adb shell pm clear com.cliquepix.clique_pix` + retry** — didn't help. (Critical signal: the rate-limit counter was keyed on JWT subject = user `oid`, so reinstalling the same user can't reset the bucket. This was the first hint.)
2. **App Insights queries on `appi-cliquepix-prod` for `/api/auth/verify` in the failure window** — Query 3 (`customEvents` filtered to `auth_verify_*`) returned `auth_verify_success` events. Backend was succeeding. So the failure was either after the backend response OR (as it turned out) was a 429 NOT generating the `auth_verify_success` event for the failed attempt while ALSO not throwing an exception in `authVerify` (because APIM rejected before reaching the function).
3. **Debug APK with `[AUTH-SIGNIN-FAIL]` debugPrint instrumentation** — added three lines to `auth_providers.dart:174-180` printing exception runtimeType, message, and (for DioException) status + body. Captured trace was definitive:
   ```
   13:16:08.451 [AUTH-SIGNIN-FAIL] type=DioException msg=DioException [bad response] ... 429
   13:16:08.451 [AUTH-SIGNIN-FAIL] dio.type=DioExceptionType.badResponse dio.status=429
                dio.body={statusCode: 429, message: Rate limit is exceeded. Try again in 1 seconds.}
   ```

**The root cause.** Phase 0+A audit (per `BETA_OPERATIONS_RUNBOOK.md §2`) found six operation-scope `<rate-limit-by-key>` policies on the `cliquepix-v1` API, all keyed on JWT Subject:

| Operation | Limit | Effect |
|---|---|---|
| `auth-verify` | 30 calls / 60s per user | **The user-blocking bug** — the 5-layer Entra refresh defense + verify-in-background + AuthInterceptor 401 retry + a few user retries can blow past 30/min for a single user in seconds |
| `upload-url` | 10 calls / 60s per user | The original incident #1-#4 limit re-emerged at op scope |
| `catch-all-delete` | 30 calls / 60s per user | Would 429 moderation/cleanup flows |
| `catch-all-patch` | 30 calls / 60s per user | — |
| `catch-all-post` | 30 calls / 60s per user | — |
| `catch-all-put` | 30 calls / 60s per user | — |

**The bigger surprise.** These weren't drift — they were declared in `bicep/apim/main.bicep` (lines 1247-1322 pre-fix; the file lived at the repo root as `main.bicep` until 2026-05-05 when it was relocated to `bicep/apim/` to make IaC discoverable). The 2026-04-29 cleanup (incident #5) deleted them in live APIM but a subsequent bicep deploy re-introduced them, leaving live and IaC contradictory: the API-scope policy in the same bicep file (line 1147) had a comment explicitly forbidding `rate-limit-by-key`, yet the operation-scope resources lower in the file were doing exactly that.

**The fix (4 phases, all completed 2026-05-05).**

| Phase | Action | Outcome |
|---|---|---|
| A | Edit `bicep/apim/main.bicep` — remove the 6 `apis/operations/policies@2025-03-01-preview` resources targeting `cliquepix-v1` operations. Replaced with one explanatory comment block at lines 1247-1260 | Source of truth fixed. Operation resources themselves (URL templates / methods at lines 840, 855, 870, 885, 900, 915, 1121) untouched — operations still route, just lose their rate-limit gate |
| B | `az rest DELETE` on each of the 6 `.../apis/cliquepix-v1/operations/{op}/policies/policy?api-version=2022-08-01` URLs. Verified each subsequent GET returns `ResourceNotFound` | Live APIM cleaned. Each operation falls through to the API-scope policy (clean: `<base/>` + CORS) |
| C | `sleep 90 && az apim api update -g rg-cliquepix-prod -n apim-cliquepix-002 --api-id cliquepix-v1 --protocols https` | Drains in-flight Developer-tier in-memory counter cache; protocols toggle (idempotent — was already https-only) forces gateway pod policy refresh |
| D | This entry + apim_policy.xml comment update (incident #6, ~70 new lines documenting the diagnosis + fix + lessons) + BETA_OPERATIONS_RUNBOOK.md §2 augmentation (the audit script DOES NOT inspect IaC; must also `grep -nE 'apis/operations/policies' bicep/apim/main.bicep`) + ARCHITECTURE.md §6 paragraph (positive design statement: abuse protection lives at application layer, not APIM) | Future agents can't repeat this mistake without ignoring three explicit prohibitions |

**Verification.**
- Live APIM probe from this dev box: `POST /api/auth/verify` (no token) returns 401 with canonical `UNAUTHORIZED` envelope, not 429. Five rapid POSTs all return 401, confirming no per-IP rate-limit either.
- On-device sign-in: lands on Events screen, no banner.
- App Insights: `auth_verify_success` event fires for the user; zero 429s in `requests` for `/api/auth/verify` in the post-fix window.
- Backup of pre-fix policy XMLs: `C:\Users\genew\AppData\Local\Temp\apim-bak-20260505-1327\` — all six policy bodies preserved verbatim if revert is ever needed (it won't be).

**Operational lessons.**
1. **The Phase 0+A audit script audits live APIM, not source.** Augment with `grep -nE 'apis/operations/policies' bicep/apim/main.bicep` so IaC declarations get caught even if live APIM is clean (or vice versa).
2. **`bicep/apim/main.bicep` is the source of truth for ALL APIM resources, including operation-scope policies.** `apim_policy.xml` covers only the API scope. The two are partially redundant (the API-scope policy XML is duplicated between `apim_policy.xml` and `bicep/apim/main.bicep` line 1147). A future cleanup should consolidate to one source.
3. **The `[AUTH-SIGNIN-FAIL]` debugPrint at `auth_providers.dart:174-180`** was the single highest-leverage diagnostic in this session. Without it we'd have spent days guessing. It costs nothing on the happy path (catch block is never entered on success) and stays in the codebase as a permanent regression-detection layer.
4. **Tier migration is the wrong tool for "rate-limit too tight" bugs.** Per Microsoft's own docs, rate-limiting at APIM is "never completely accurate" on any tier — Basic v2's token-bucket algorithm is modestly more burst-friendly than Developer's sliding-window, but the same 30/60 limit will 429 a user storm just as effectively. The prohibition on re-adding `rate-limit-by-key` in `apim_policy.xml` should hold even if/when we move off Developer; the prerequisite for re-introducing one is LOAD-TESTING against actual traffic, not tier upgrade.

**The unrelated `MsalClientException current_account_mismatch` at trace timestamp 13:15:57** was caught gracefully by the `msg.contains('Msal')` branch in `auth_providers.dart:193`, transitioned to `AuthUnauthenticated` (clean LoginScreen, no banner). Known transient MSAL hiccup on first-attempt-after-fresh-install. NOT a bug — `resetSession()` clears state and the next attempt succeeds.

**Rollback plan.** Restore `bicep/apim/main.bicep` lines 1247-1322 from `git show HEAD:bicep/apim/main.bicep` AND PUT the 6 backup policy XMLs from `apim-bak-20260505-1327\` back via `az rest PUT`. Both source and live state would revert. There is no plausible reason to do this — the prior state was an unintentional regression of the API-scope policy's design intent — but the path is documented for completeness.

---

## iOS account-switching trapped in previous user's CIAM session — fixed (2026-05-04)

**Status:** ✅ code complete (3 line-changes + comments), ✅ flutter analyze 54-issue baseline preserved, ✅ flutter test 82/82 green, ✅ release IPA built + installed on Gene's iPhone (00008120-001965E014C3601E, iOS 26.4.2) in 22.2s, ✅ on-device verified by Gene Whitley 2026-05-04 — sign-out as user A → sign-in attempt as user B no longer traps on CIAM "Continue as A" prompt. **Pending:** Android regression check on Samsung, commit + push to main, doc updates merged.

**The user complaint.** On iPhone, after signing out as user A (Google federated, e.g. `genewhitley2017@gmail.com`) and tapping Get Started to sign in as user B (e.g. `paulawhitley2017@gmail.com`), CIAM (`cliquepix.ciamlogin.com`) silently recognized user A's session and showed *"Are you trying to sign in to CLIQUE Pix?"* with A's email pre-recognized. Continue → signed back in as A directly with NO password re-prompt (the cookie did the auth). Cancel → returned to LoginScreen with no escape; every subsequent Get Started repeated the same prompt forever. **Android did not reproduce** with the same accounts. The only known workaround pre-fix was uninstall-and-reinstall.

**The root cause — confirmed by reading `msal_auth` 3.3.0 iOS source.** `~/.pub-cache/hosted/pub.dev/msal_auth-3.3.0/ios/Classes/MsalAuthPlugin.swift:220` unconditionally sets `webViewParameters.prefersEphemeralWebBrowserSession = true` on iOS 13+ — the intent is fresh cookie jar per sign-in. But the very next switch (lines 221-236) overrides `webviewType` based on `MsalAuth.broker`:

- `safariBrowser` → `webviewType = .safariViewController` ← **THE BUG**
- `webView` → `.wkWebView`
- default (any other string, including `msAuthenticator`) → `.default` (ASWebAuthenticationSession on iOS 13+)

`prefersEphemeralWebBrowserSession` is an ASWebAuthenticationSession-only API. SFSafariViewController **silently ignores** the flag and uses its iOS-11+ per-app **persistent** cookie jar. CIAM's session cookie at `cliquepix.ciamlogin.com` survived `pca.signOut()` (which only clears the MSAL keychain at `com.microsoft.adalcache`, not the cookie jar). The next `acquireToken` opened SFSafariViewController, sent the cookie, and CIAM completed auth silently via the cookie — `Prompt.login` was bypassed because the cookie did the auth before any prompt was rendered.

**Why Android wasn't affected.** Android MSAL reads `"authorization_user_agent": "BROWSER"` and `"browser_sign_out_enabled": true` from `app/assets/msal_config.json`. On signOut, Android MSAL navigates to the OIDC `oauth2/v2.0/logout` endpoint inside Chrome Custom Tabs and clears the cookie server-side. iOS doesn't read `msal_config.json` at all (`utils.dart:39` shows the `broker` field is iOS-only; the JSON file path is only on `AndroidConfig`) — `browser_sign_out_enabled` is dead config on iOS. Same JSON file, totally different platform code paths.

**The fix.** Change `Broker.safariBrowser` → `Broker.msAuthenticator` at all 3 PCA-creation call sites:

| File | Line | Change |
|---|---|---|
| `app/lib/features/auth/domain/auth_repository.dart` | 58 | `Broker.safariBrowser` → `Broker.msAuthenticator` (+ explanatory comment) |
| `app/lib/main.dart` | 81 | same change (+ comment) |
| `app/lib/features/auth/domain/background_token_service.dart` | 68 | same change (+ comment) |

`Broker.msAuthenticator` routes msal_auth into the `default:` webviewType branch → ASWebAuthenticationSession on iOS 13+ → `prefersEphemeralWebBrowserSession=true` is now effective → each interactive sign-in gets a fresh ephemeral cookie jar that's destroyed at session end. **Cookies cannot persist across sign-ins by construction.** The enum name is misleading: for our B2C/CIAM tenant, MSAL never brokers via the Microsoft Authenticator app (B2C is unsupported by Authenticator broker), so the actual behavior is "use ASWebAuthenticationSession with ephemeral session." `LSApplicationQueriesSchemes` (`msauthv2`, `msauthv3`) already in `Info.plist` satisfies the `MSALGlobalConfig.brokerAvailability=.auto` requirement that this enum value brings. Background-isolate sites (Layer 2 silent push, Layer 4 WorkManager) only run `acquireTokenSilent` (no browser opens), so the broker value is functionally irrelevant there — but `MsalAuth.broker` is a process-wide Swift static and last-write-wins, so consistency across PCA-creation sites avoids static-state clobbering between isolates.

**UX side-effect.** iOS shows a one-time-per-session system prompt — *"'CLIQUE Pix' Wants to Use 'cliquepix.ciamlogin.com' to Sign In — This allows the app and website to share information about you."* — before the auth flow opens. Standard iOS OAuth UX (Reddit, Discord, Twitter all show it). With ephemeral session it may appear every sign-in (no SSO state to remember). Acceptable trade-off vs the bug.

| Phase | Status | Files |
|---|---|---|
| Phase 0 verification — msal_auth 3.3.0 iOS source inspected | ✅ | (read-only) |
| Edits at 3 PCA creation sites | ✅ | as listed above |
| `flutter analyze` 54-issue baseline preserved | ✅ | — |
| `flutter test` 82/82 green | ✅ | — |
| iOS release build + install on Gene's iPhone | ✅ Verified 2026-05-04 | — |
| Reproduction test on iPhone (Gene → sign out → Paula → sign out → Gene) | ✅ Verified 2026-05-04 | — |
| Docs: `CLAUDE.md` Frontend deps section, `ARCHITECTURE.md` iOS MSAL Platform Configuration, `ENTRA_REFRESH_TOKEN_WORKAROUND.md` Known unknowns table, this entry | ✅ | as listed |
| Android regression test on Samsung (sign-out → switch account) | ⏳ Pending | — |
| Commit + push to main | ⏳ Pending | — |
| 24h telemetry soak — Layer 2/3/4 background-isolate health | ⏳ Pending | — |

**Telemetry to watch (App Insights).** Background isolate paths (Layer 2 silent push, Layer 4 WorkManager) should be unaffected by the broker change since they only run `acquireTokenSilent`. Soak query:
```kql
customEvents
| where timestamp > ago(24h)
| where name in ("silent_push_refresh_success", "silent_push_refresh_failed",
                 "wm_refresh_success", "wm_refresh_failed",
                 "foreground_refresh_success", "foreground_refresh_failed")
| summarize count() by name, bin(timestamp, 1h)
```
**Healthy:** rates within ±20% of pre-deploy baseline. A spike in `silent_push_refresh_failed` or `wm_refresh_failed` would indicate the broker change accidentally affected silent acquisition (unexpected — silent acquisition doesn't open a browser).

**Residual risks (acknowledged, not blocking).**
- **Microsoft Authenticator-installed iPhone:** B2C is documented as unsupported by Authenticator broker; MSAL falls through to web flow. Vanishingly few CLIQUE Pix consumer users have Authenticator installed. If beta users report sign-in failures, check telemetry for `WORKPLACE_JOIN_REQUIRED` / `INTERACTION_REQUIRED` codes.
- **Federated Google sign-in via ASWebAuthenticationSession:** ASWebAuthenticationSession is Safari-backed, uses standard Safari User-Agent, passes Google's "no embedded webview" rule. Verified by Gene's on-device test 2026-05-04.
- **Pre-fix iOS users have stale cookies in the SFSafariViewController per-app jar:** new code never opens SFSafariViewController, so those orphaned cookies are unreachable and harmless. They expire on CIAM's tenant-default session lifetime (~24h).

**Rollback plan.** Single revert: `git checkout app/lib/features/auth/domain/auth_repository.dart app/lib/main.dart app/lib/features/auth/domain/background_token_service.dart`. Pre-existing buggy behavior returns. No backend, no infra, no migration, no portal config to undo.

---

## iPhone-recorded video plays sideways on Android viewer — fixed (2026-05-04)

**Status:** ✅ code complete, ✅ transcoder build green + 24/24 new jest tests, ✅ backend build green + 164/164 jest tests preserved, ✅ backend deployed via `func azure functionapp publish func-cliquepix-fresh`, ✅ transcoder image v0.1.7 built + pushed to ACR (`sha256:b4da3290aea83393b7d87488eb18725a9c15adc0961e9cabeeffcec2b0cc57f8`), ✅ `caj-cliquepix-transcoder` Container Apps Job updated to v0.1.7, ✅ end-to-end verified on iPhone-uploader → Samsung-viewer 2026-05-04. **Pending:** 24h telemetry soak.

**The user complaint.** Beta tester uploaded a portrait video recorded on her iPhone. On her own iPhone the video played correctly. On the Samsung viewer it played rotated 90° CCW — `video07.png` shows the dog sideways with the floor on the right and a window on the left, framed inside a portrait player canvas.

**The root cause.** iPhones record at the sensor's native landscape orientation and store a rotation hint in the MOV container — either the legacy `tags.rotate` mov atom (older iOS) or the modern `Display Matrix` side-data structure (iOS 14+, ffprobe surfaces a canonical `rotation` value, typically negative). AVPlayer / Safari / direct-MOV ExoPlayer honor this hint at playback. Our transcoded delivery did not:
- The fast path (`-c copy`) writes HLS MPEG-TS segments. **MPEG-TS has no rotation atom.** With stream-copy the rotation hint is silently dropped, ExoPlayer plays raw landscape pixels in a portrait viewport.
- The MP4 fallback branch *sometimes* preserved rotation (FFmpeg-version-dependent, unreliable across the source iOS × target Android matrix).

Latent the entire video-v1 cycle because (a) the uploader plays from the local file via Decision 13 (rotation atom intact, AVPlayer honors it); (b) iOS viewers go to MP4 directly via Decision 15 and *sometimes* got correct playback; (c) Android viewers always tried HLS first and always lost. The bug surfaced when an iPhone uploader and a Samsung viewer were in the same beta-test event.

**The fix.** Server-side bake-in via the slow path. Five coordinated edits across two packages:

1. **`backend/transcoder/src/ffmpegService.ts`**: new `extractRotation` helper reads `Display Matrix` side data first (canonical), falls back to `tags.rotate`, normalizes to 0/90/180/270. New `computeOutputDimensions` predicts output W×H from source dims + rotation (used by the runner instead of an extra ffprobe round-trip on the output). `canStreamCopy` gains `if (probe.rotation !== 0) return false` — rotated sources MUST go through the slow path because `-c copy` cannot bake rotation into pixels. The slow-path FFmpeg invocation gains `-metadata:s:v:0 rotate=0` (suppresses residual legacy rotation atom on the MP4 output to prevent player double-rotation; no-op on MPEG-TS) and replaces the landscape-only `scale=-2:min(ih,1080)` with the orientation-agnostic `scale=min(1920\,iw):min(1920\,ih):force_original_aspect_ratio=decrease` (caps long edge at 1920 — without this, iPhone portraits would be crushed to 608×1080 the moment they hit the slow path).
2. **`backend/transcoder/src/types.ts`**: `rotation: 0 | 90 | 180 | 270` added to `FfprobeResult.valid:true`. `source_rotation?: 0 | 90 | 180 | 270` added to `CallbackSuccessPayload` (optional for forward-compat with rolled-back transcoder images).
3. **`backend/transcoder/src/runner.ts`**: imports `computeOutputDimensions`, uses it for slow-path callback `width`/`height`, passes `source_rotation: probeResult.rotation` through, logs rotation alongside the existing dimension log.
4. **`backend/src/functions/videos.ts`**: `CallbackBody` interface gains `source_rotation?`. The `video_transcoding_completed` `trackEvent` properties block gains `sourceRotation: String(body.source_rotation ?? 0)` — App Insights now exposes the rotation distribution.
5. **`backend/transcoder/src/__tests__/rotation.test.ts`** (new): 24 unit tests covering rotation extraction (legacy tag, Display Matrix, precedence rules, non-cardinal angles, unparseable input), `canStreamCopy` rotation gating (regression check the existing rules still pass for rotation=0), and `computeOutputDimensions` (1080p/4K landscape and portrait, 180° flip, even-dimension guarantee, odd-source rounding).

We rely on FFmpeg 6's default `autorotate` behavior — the decoder rotates frames to displayed orientation BEFORE the encoder writes pixels. We do NOT add an explicit `transpose` filter; that would force us to maintain rotation-direction conversion logic (CW vs CCW, modern vs legacy convention) ourselves. We only branch on `rotation === 0` vs not for path selection. The Dockerfile pin (`jrottenberg/ffmpeg:6-alpine@sha256:464...`) is locked specifically to limit the risk of an autorotate-default change in a future FFmpeg release.

| Phase | Status | Files |
|---|---|---|
| Transcoder: ffprobe rotation extraction + canStreamCopy gate + slow-path filter changes | ✅ | `backend/transcoder/src/ffmpegService.ts` |
| Transcoder: types | ✅ | `backend/transcoder/src/types.ts` |
| Transcoder: runner uses computeOutputDimensions + sends source_rotation | ✅ | `backend/transcoder/src/runner.ts` |
| Backend: CallbackBody.source_rotation? + telemetry dimension | ✅ | `backend/src/functions/videos.ts` |
| Transcoder: jest setup + 24 unit tests | ✅ | `backend/transcoder/jest.config.js`, `backend/transcoder/package.json`, `backend/transcoder/tsconfig.json`, `backend/transcoder/src/__tests__/rotation.test.ts` |
| Transcoder: `npm run build` clean | ✅ | — |
| Transcoder: `npm test` 24/24 | ✅ | — |
| Backend: `npm run build` clean | ✅ | — |
| Backend: `npm test` 164/164 (preserved) | ✅ | — |
| Docs: VIDEO_ARCHITECTURE_DECISIONS Decision 16, BETA_TEST_PLAN §5 row, BETA_OPERATIONS_RUNBOOK troubleshooting entry, CLAUDE.md slow-path note + Decision count, ARCHITECTURE.md Decision count, this entry | ✅ | as listed |
| Backend deploy (`func azure functionapp publish func-cliquepix-fresh`) | ✅ Deployed 2026-05-04 — health 200 via direct + Front Door | — |
| Transcoder image v0.1.7 build + push (`docker build -t cracliquepix.azurecr.io/cliquepix-transcoder:v0.1.7 . && az acr login --name cracliquepix && docker push ...`) | ✅ Pushed 2026-05-04, digest `sha256:b4da3290aea83393b7d87488eb18725a9c15adc0961e9cabeeffcec2b0cc57f8` | — |
| Container Apps Job update (`az containerapp job update -n caj-cliquepix-transcoder -g rg-cliquepix-prod --image cracliquepix.azurecr.io/cliquepix-transcoder:v0.1.7`) | ✅ Live 2026-05-04 — `az containerapp job show ... --query 'properties.template.containers[0].image'` returns `:v0.1.7` | — |
| Two-device verification (iPhone uploader → Samsung viewer, plus regression cases) per BETA_TEST_PLAN §5 | ✅ Verified 2026-05-04 — iPhone-portrait video plays UPRIGHT on Samsung viewer | — |
| 24h telemetry soak: confirm `sourceRotation` distribution and zero `rot != 0 + stream_copy` rows | ⏳ Pending | — |

**Telemetry to watch (App Insights `customEvents`):**
```kql
customEvents
| where name == "video_transcoding_completed"
| where timestamp > ago(7d)
| extend rot = toint(customDimensions.sourceRotation),
         mode = tostring(customDimensions.processingMode)
| summarize count() by rot, mode
```
Healthy: ~30–50% of all uploads show `rot=90` (or `rot=270`) and `mode=transcode`. **Any `rot != 0, mode == stream_copy` row is a bug** — `canStreamCopy` should have rejected it.

**Deploy ordering** (forward-compatible): backend FIRST (gains the optional `source_rotation` callback field — old transcoder image continues working unchanged), then transcoder image v0.1.7. Atomic on the Container Apps Job side — next queue dequeue uses new code.

**Cost / latency impact.** iPhone landscape videos: unchanged (~3 s fast path). iPhone portrait H.264 SDR: ~3 s → ~10–15 s slow path. iPhone HEVC HDR: unchanged (~21 s slow path was already being used; now also rotates correctly). Android landscape: unchanged. Android portrait with modern Display Matrix: ~3 s → ~10–15 s slow path (incidental win — was also broken pre-fix). Uploader-perceived latency: **zero** (Decision 13's local-first playback). Other clique members waiting for `video_ready`: ~7–12 s longer for affected videos. Compute cost: ~$0.001 per affected video, ~$0.05/month at MVP scale. Negligible.

**Out of scope (tracked for follow-up).**
- Reprocessing already-transcoded rotated videos in current events (events expire ≤ 7 days; not worth a one-shot script).
- Switching HLS segment format from MPEG-TS to fMP4 (would let `-c copy` preserve rotation natively but is a much larger architectural change; revisit if/when adaptive bitrate ladder ships).
- `app/lib/features/videos/presentation/video_card_widget.dart` aspect-ratio-aware poster card (currently `BoxFit.cover` at fixed 300 px tall — center-crops portrait posters in the feed). Separate UX PR; doesn't affect playback correctness.

**Rollback plan.** `az containerapp job update -n caj-cliquepix-transcoder -g rg-cliquepix-prod --image cracliquepix.azurecr.io/cliquepix-transcoder:v0.1.6`. New uploads revert to broken-rotation behavior; in-flight transcodes finish on whichever image was running when they started. Backend `CallbackBody.source_rotation?` is optional, so v0.1.6 callbacks (which don't send the field) continue working without rolling the backend back.

---

## Raw DioException leak on session-expired 401 — fixed (2026-05-03)

**Status:** ✅ code complete, ✅ `flutter analyze` 54-issue baseline preserved, ✅ `flutter test` 82/82 green, ✅ committed `0d1ffcb` and pushed to `main`. **Pending:** APK + IPA build for broader rollout, on-device verification of the `welcome_back_shown { source=interceptor }` telemetry split.

**The user complaint.** Returning iPhone user (cached MSAL token from 2 days ago — past Entra's hardcoded 12-hour inactivity timeout) saw a raw error message on the home screen verbatim: *"DioException [bad response]: This exception was thrown because the response has a status code of 401 and RequestOptions.validateStatus was configured to throw for this status code. The status code of 401 has the following meaning: 'Client error - the request contains bad syntax or cannot be fulfilled'..."*. The 5-layer Entra defense's Layer 5 (WelcomeBackDialog) eventually appeared but was racing the AsyncError UI to the screen — and losing.

**The bug chain.** Cold start with stale token + no list cache (returning user predates the 2026-05-03 cold-start cache rollout):

1. `main()` reads cached token + UserModel from secure storage → `bootstrapState = AuthAuthenticated(cachedUser)`
2. Router resolves `AuthAuthenticated` → renders `/events` → `HomeScreen.build`
3. `HomeScreen` watches `allEventsListProvider`. `AllEventsNotifier.build()` sees `cached == null` (no cache yet) → calls `repo.listAllEvents()` directly — **no try/catch**
4. Backend returns 401 (token past 12h inactivity)
5. `AuthInterceptor.onError` catches the 401 → tries `tokenStorage.refreshToken()` (the bool variant) → MSAL `acquireTokenSilent` fails with `AADSTS700082` → `refreshed = false` → falls through and propagates the original `DioException` via `handler.next(err)`. **The interceptor only `debugPrint`'d the failure — it did NOT signal `AuthNotifier`**, so `AuthAuthenticated` state persisted
6. `AllEventsNotifier.build()` had no error handling → AsyncNotifier transitions to `AsyncError(DioException)`
7. `home_screen.dart:292` rendered `eventsAsync.error.toString()` → "DioException [bad response]: ..." text painted to screen
8. Concurrently, `_verifyInBackground` (also fired by AuthNotifier on AuthAuthenticated bootstrap) was running its own `silentSignIn` — it eventually failed with the same AADSTS700082, matched `_handleSilentSignInFailure`'s session-expired regex, and transitioned state to `AuthReloginRequired`. GoRouter redirected to `/login` → WelcomeBackDialog appeared
9. **The user saw the raw DioException for ~1-2 seconds before WelcomeBackDialog overlaid it**

**The fix.** Two coordinated changes in one commit (`0d1ffcb`), three files:

1. **`home_screen.dart`** — replace `eventsAsync.error.toString()` and `cliquesAsync.error.toString()` with the existing `friendlyApiErrorMessage(err, resourceLabel: ...)` helper from `core/utils/api_error_messages.dart` which explicitly never returns raw `DioException` toString. Maps 401/403/timeout/5xx to human-readable messaging.

2. **`auth_interceptor.dart` + `auth_providers.dart`** — root-cause coordination:
   - Interceptor switches from `tokenStorage.refreshToken()` (bool) to `authRepository.refreshTokenDetailed()` (`RefreshResult` with structured `errorCode`)
   - On refresh failure with session-expired pattern (`AADSTS700082` / `AADSTS500210` / `no_account_found`): fires `AuthNotifier.triggerWelcomeBackOnSessionExpiry(reason: errorCode)` fire-and-forget. Auth state transitions immediately, racing the AsyncError to the screen
   - New public `triggerWelcomeBackOnSessionExpiry({reason})` on AuthNotifier with state guard against double-firing (no-op if already in `AuthReloginRequired` / `AuthUnauthenticated` / `AuthLoading`)
   - `_triggerWelcomeBack` refactored to accept optional `source` / `reason` for telemetry splitting — `welcome_back_shown { source: 'interceptor' | 'lifecycle' }` lets us measure fix effectiveness in App Insights
   - The session-expired regex is now in THREE sites in sync: `AuthRepository._extractAadstsCode`, `AuthNotifier._handleSilentSignInFailure`, and `AuthInterceptor._isSessionExpired` — comment on each notes the others. Adding a new pattern (e.g., a future Entra error code) requires updating all three

**TimeoutException on refresh intentionally does NOT trigger welcome-back** — a hung MSAL is more likely a network hiccup than session-expiry, and Layer-3 on-resume retries cleanly. Logging out on transient timeout would be worse UX than the brief AsyncError flicker (which now shows a friendly message anyway).

| Phase | Status | Files |
|---|---|---|
| Fix 1: home_screen renders friendly error (no raw `error.toString()`) | ✅ | `app/lib/features/home/presentation/home_screen.dart` |
| Fix 2: interceptor → notifier session-expired signal + telemetry split | ✅ | `app/lib/services/auth_interceptor.dart`, `app/lib/features/auth/presentation/auth_providers.dart` |
| `flutter analyze` 54-issue baseline | ✅ | — |
| `flutter test` 82/82 | ✅ | — |
| Commit + push | ✅ `0d1ffcb` | — |
| Docs: DEPLOYMENT_STATUS (this), CLAUDE.md, BETA_TEST_PLAN §1, BETA_OPERATIONS_RUNBOOK | ✅ | as listed |
| TestFlight / APK rollout for broader beta | ⏳ Pending | — |
| 24-72h telemetry soak: confirm `welcome_back_shown { source=interceptor }` rows appear and the AsyncError-then-WelcomeBack flicker is gone | ⏳ Pending | — |

**Telemetry to watch (App Insights `customEvents`):**
```kql
customEvents
| where timestamp > ago(7d)
| where name == "welcome_back_shown"
| extend source = tostring(customDimensions.source),
         reason = tostring(customDimensions.reason)
| summarize count() by source, reason
```
Healthy after fix lands: `source=interceptor` rows appear when stale tokens 401 mid-app-use (specifically: returning users who haven't opened the app in >12h on a screen that makes an API call). `source=lifecycle` (or empty for legacy events) is the on-resume Layer-3 path. The `reason` dimension carries the MSAL error code (`AADSTS700082` etc).

**Out of scope (tracked for future).**
- Audit the rest of the codebase for other `SnackBar(content: Text('Failed to X: $e'))` patterns that could leak DioExceptions on local actions (delete account, delete photo, share video, etc.) — narrow scopes, but worth a sweep
- Promote `[VPS]` debugPrints from the prior video PR to App Insights `trackEvent` for visibility
- Add a "stale-token cold-start" regression test to `BETA_TEST_PLAN.md` §1 — synthetically expire the token and verify the user lands on WelcomeBack within a frame, never sees a raw error
- Consider extracting the session-expired matcher into a shared helper used by all three sites (low priority — the comment block keeps the three in sync)

**Rollback plan:** revert `0d1ffcb`. Three-file change, no backend, no infra, no migration. Pre-existing behavior (raw error leak + delayed WelcomeBack) returns.

---

## iPhone video playback hang — fixed (2026-05-03)

**Status:** ✅ code complete, ✅ verified on tethered iPhone (iOS 26.4.2) — cloud video plays within ~3-5s, no forever spinner. ✅ `flutter analyze` 54-issue baseline preserved. ✅ `flutter test` 82/82 green.

**The user complaint.** Every cloud video tap on iPhone resulted in a forever spinner — the `_isLoading == true` state never flipped. Local-first uploader playback also reported as hanging. Android worked fine.

**The root cause.** A documented (but not previously hit) iOS AVPlayer limitation: `VideoPlayerController.networkUrl(Uri.file(<m3u8 path>), formatHint: VideoFormat.hls)` with a manifest whose segment lines are absolute `https://*.blob.core.windows.net/...` SAS URLs leaves `AVPlayerItem` in `Status: Unknown` indefinitely. `controller.initialize()` returns a `Future` that NEVER resolves and NEVER throws — so the existing `try/catch` HLS-then-MP4-fallback flow never engaged. ExoPlayer (Android) handles cross-scheme playlist→segment fine, which masked the bug for the entire prior testing window. The "every video hangs" report was misleading: the cloud HLS path hangs hard; local-first and instant-preview paths were collateral damage from the lack of a fail-safe (no init timeout, no controller dispose-on-failure → orphaned `AVPlayerItem` could wedge subsequent attempts).

**The fix.** Two coordinated changes in `app/lib/features/videos/presentation/video_player_screen.dart`, single file:

1. **iOS skips HLS, goes straight to MP4** — new `_iosForcedMp4` state flag, `Platform.isIOS` branch in `_initializePlayer` cloud tier (after `repo.getPlayback()`) that calls `_initWithMp4(playback)` directly and returns. v1 is single-rendition HLS so MP4 progressive download with `+faststart` is functionally equivalent. Caption logic in `_buildBody` gates the misleading "Playing standard quality" caption on `!_iosForcedMp4` so iOS users don't see degraded-service messaging on their primary path. Android keeps the HLS-first flow unchanged.
2. **Universal init-timeout safety net** — new `_initWithTimeout(controller, duration, tier)` helper wraps every `controller.initialize()` site in `_initializePlayer`, `_initWithHls`, `_initWithMp4`. 8s for local-file tier, 15s for instant-preview / HLS / MP4 tiers. On `TimeoutException` (or any exception): disposes the controller before rethrowing — critical on iOS where an orphaned `AVPlayerItem` can wedge subsequent player attempts. Outer `catch` differentiates `TimeoutException` ("Playback didn't start in time. Tap back and try again.") from generic init failure ("We couldn't play this video. Please try again later."). Mounted-race fix on both `_wireChewie` and `_wireChewieFromController` — disposes the controller cleanly when the user navigates away during init. Persistent `[VPS]` `debugPrint` markers at every step so future iOS playback regressions can be triaged with `flutter run --release` + Xcode device console in minutes instead of hours.

**Why both changes ship together.** The safety net alone makes the user-visible symptom recoverable (15s wait then MP4 plays via existing fallback) — verified on-device. But every iPhone user would eat the 15s wait on every cloud playback. The iOS HLS skip eliminates the wait entirely. The safety net is the long-term insurance — even if a future regression introduces a new hang, the user gets a friendly error instead of forever-spinner.

| Phase | Status | Files |
|---|---|---|
| Phase 3 safety net (timeouts, dispose-on-failure, mounted-race fix, [VPS] logs) | ✅ | `app/lib/features/videos/presentation/video_player_screen.dart` |
| Phase 2A iOS HLS skip (Platform.isIOS branch + `_iosForcedMp4` flag + caption gate) | ✅ | same file |
| `flutter analyze` 54-issue baseline | ✅ | — |
| `flutter test` 82/82 | ✅ | — |
| Tethered-iPhone release-build verification (Gene's iPhone, iOS 26.4.2) | ✅ Verified 2026-05-03 | — |
| Docs: DEPLOYMENT_STATUS (this), CLAUDE.md, BETA_TEST_PLAN §5, BETA_OPERATIONS_RUNBOOK, VIDEO_ARCHITECTURE_DECISIONS Decision 15 | ✅ | as listed |
| Commit + push | ⏳ Pending | — |
| TestFlight release build for broader beta | ⏳ Pending | — |

**Diagnostic process — recorded for future regressions.** The bug was hard to catch because:
- The symptom was "spinner spins forever" — no error, no crash, no exception in the catch path
- iOS device testing in beta had primarily exercised the local-first uploader path (which works on iOS without HLS), so the cloud HLS hang was latent for the entire video v1 ship cycle
- `flutter run --debug` on iOS 26.x triggers the LLDB launch-watchdog issue documented in BETA_OPERATIONS_RUNBOOK, so the user couldn't easily attach for live diagnosis. `flutter run --release` was the workable path
- The "blank white screen on profile-mode launch" the user reported turned out to be a red herring — it was just slow profile-mode startup + `flutter run` failing to attach VM service, NOT a `main()` hang. The cold-start refactor (commit 3f882a3) was briefly suspected but cleared

The investigation took: 1× full-codebase Explore, 1× backend Explore, 1× iOS native Explore, 1× Plan agent for architecture validation, 1× device-tethered release deploy, 1× user-confirmed end-to-end test. Total wall-clock ~3 hours from first symptom report to verified fix.

**Telemetry to watch (post-deploy soak).**
```kql
customEvents
| where timestamp > ago(7d)
| where name in ("video_init_timeout", "video_played")
| extend tier = tostring(customDimensions.tier),
         platform = tostring(customDimensions.platform)
| summarize count() by name, tier, platform
```
Expect on iOS: `video_played` with `tier=mp4` (the iOS-forced path) at non-zero count; `video_init_timeout` at near-zero. Any non-zero timeout on iOS within 7 days indicates a remaining hang scenario worth investigating. (Telemetry events are TBD — currently we only have `[VPS]` debugPrints; promoting to App Insights `trackEvent` is a separate hygiene PR.)

**Out of scope (tracked for v1.5).**
- Backend raw-m3u8 endpoint (`GET /api/videos/{id}/playback.m3u8` returning manifest with `Content-Type: application/vnd.apple.mpegurl`) — would let iOS use HTTPS-served HLS instead of `file://` workaround, unblocking adaptive bitrate ladders. Not needed for v1 (single-rendition HLS = MP4-equivalent). Has auth-token-staleness complications since `VideoPlayerController` bypasses Dio's `AuthInterceptor`.
- App Insights `trackEvent` for the `[VPS]` diagnostic events — currently `debugPrint` only.
- Two-device cross-platform iOS verification gate added to BETA_TEST_PLAN.md §5 (so the next time something like this slips through the cracks, it's caught before user reports).
- Investigate why iOS device testing missed this — likely cause: solo dev tested as the uploader (local-first path always succeeds on iOS) and never exercised the cloud HLS path as a clique-mate viewer.

**Rollback plan:** revert the commit. Single-file change, no backend, no infra, no migration. Pre-existing HLS-then-MP4-fallback flow is unchanged on Android.

---

## Cold-start Home spinner eliminated — stale-while-revalidate cache (2026-05-03)

**Status:** ✅ code complete, ✅ flutter analyze 54-issue baseline preserved, ✅ flutter test 82/82 green (was 70 + 12 new). **Pending:** APK build → on-device verification per `BETA_TEST_PLAN.md` §11 → commit + push.

**The user complaint.** *"When I start the application it spins for about 15 seconds to 30 seconds before it shows the Events listed."* CLAUDE.md's existing rule prohibits exactly this — the optimistic-auth bootstrap was supposed to land users on Events as the first frame. But once the router resolved to `/events`, `home_screen.dart` rendered a full-screen `CircularProgressIndicator` until BOTH `allEventsListProvider` AND `cliquesListProvider` returned AND a `SharedPreferences` read for the "How it works" banner completed. On a cold backend (Functions Consumption cold-start + cold pg pool + first User Delegation Key fetch + per-event creator-avatar SAS signs) that was 10–15 s of API time on top of 5–10 s of `main()` awaits for Workmanager + notifications + tz init.

**The fix.** Two parallel changes:

1. **Tier 1a — Stale-while-revalidate.** Persist last-known events + cliques to `SharedPreferences` (versioned, user-scoped JSON). On cold start, `main()` reads both with a 250 ms timeout and overrides two new bootstrap providers in `ProviderScope`. The `AsyncNotifier`s seed from those overrides during `build()` and return cached data synchronously, then `Future.microtask(_refreshSilently)` in the background. **Hard rule: refresh failures must NOT push `AsyncError` over cached `AsyncData`** — they go to a dedicated `eventsRefreshErrorProvider` / `cliquesRefreshErrorProvider` that drives an inline "Couldn't refresh — tap to retry" pill. Cache writes are isolated in their own try/catch so a write failure can't promote to a refresh error.
2. **Tier 1c — Deferred non-critical `main()` init.** `Workmanager.initialize`, `flutter_local_notifications.initialize` + 2× `createNotificationChannel` + `requestNotificationsPermission`, `tz.initializeTimeZones` + `FlutterTimezone.getLocalTimezone`, and `FirebaseMessaging.onMessage.listen` registration moved out of `main()` into `performDeferredInit()`, called from `_CliquePixState.initState` via post-frame callback. `Firebase.initializeApp()` and `FirebaseMessaging.onBackgroundMessage(...)` MUST stay before `runApp()`.

**Tier 2 (backend pool warmup, Function App plan migration) is deferred until telemetry confirms it's needed.** The new `home_first_render_ms` and `home_first_fresh_data_ms` events let us measure: returning-user p95 should hit < 1 s (Tier 1 win); first-fresh-data p95 > 5 s would be the trigger for Tier 2.

| Phase | Status | Files |
|---|---|---|
| Cache infrastructure (3 new files) | ✅ | `app/lib/core/cache/list_cache_service.dart`, `app/lib/core/cache/list_bootstrap_providers.dart`, `app/lib/core/cache/last_refresh_error_provider.dart` |
| Add `toJson()` to `EventModel` + `CliqueModel` for cache serialization | ✅ | `app/lib/models/event_model.dart`, `app/lib/models/clique_model.dart` |
| Refactor events + cliques providers to seed-from-cache + silent refresh + isolated cache writes | ✅ | `app/lib/features/events/presentation/events_providers.dart`, `app/lib/features/cliques/presentation/cliques_providers.dart` |
| List skeleton (3 shimmer cards) for true first-launch | ✅ | `app/lib/widgets/list_skeleton.dart` (new, uses existing `LoadingShimmer`) |
| Drop blocking spinner gate from HomeScreen + inline refresh/error pill + telemetry hooks | ✅ | `app/lib/features/home/presentation/home_screen.dart` |
| Defer Workmanager + notifications + tz to post-frame; seed cache providers in `runApp` | ✅ | `app/lib/main.dart`, `app/lib/app/app.dart` |
| Clear list caches on `signOut` / `deleteAccount` / `resetSession` | ✅ | `app/lib/features/auth/domain/auth_repository.dart` |
| Tests: cache round-trip, corrupt-prefs clears, 50/30 truncation, per-user isolation, optimistic seed, refresh-failure preserves cached state, refresh-success clears error | ✅ | `app/test/list_cache_service_test.dart` (new, 9 tests), `app/test/events_provider_optimistic_test.dart` (new, 3 tests) |
| `flutter analyze` 54-issue baseline | ✅ | — |
| `flutter test` 82/82 (was 70 + 12 new) | ✅ | — |
| Docs: PRD §5.1, ARCHITECTURE §12, CLAUDE.md Real-Time, BETA_TEST_PLAN §11, BETA_OPERATIONS_RUNBOOK §7, this entry | ✅ | as listed |
| APK build + on-device verification (cached / airplane / first-install / multi-account) | ⏳ Pending | — |
| Commit + push | ⏳ Pending | — |

**Telemetry events** (App Insights `customEvents`, fired by `home_screen.dart`):
- `home_first_render_ms { ms, hadCache }` — fires the first time HomeScreen returns non-skeleton content. Tier 1 success metric. **Target: p95 < 1 s when `hadCache=true`.**
- `home_first_fresh_data_ms { ms }` — fires when the silent refresh actually lands. Tier 2 trigger. **Target: p95 < 5 s; if higher for 2+ days, ship Tier 2 pool warmup.**

**Deploy order:** mobile-only change. APK build → manual smoke per BETA_TEST_PLAN §11 → commit (docs first) → push to main.

**Rollback plan:** revert the commit. The cache files self-clean on next sign-out (`ListCacheService().clearAll()` in `auth_repository.dart`). No backend, no migration, no infra to roll back.

**Out of scope (tracked for follow-up):** Function App plan migration to Premium / Flex Consumption (~$50–100/mo, eliminates cold start); pg pool warmup at top of `authVerify`/`listAllEvents`/`listCliques` handlers; eliminating the 8 s 401-refresh penalty in `AuthInterceptor` (defer-and-retry pattern); persisting `getUserDelegationKey` across Function App restarts; web client cold-start parity (different runtime + cache primitives).

---

## "Who reacted?" reactor list (2026-05-02)

**Status:** ✅ code complete, ✅ backend tsc + jest 164/164 green, ✅ flutter analyze 54-issue baseline preserved, ✅ flutter test 70/70 green, ✅ web `vite build` green (2168 modules, 433.97 KB initial JS / 140.58 KB gzip — within budget). **Pending:** backend deploy → APK + web ship → on-device verification per `BETA_TEST_PLAN.md` §4 / §5 / §12.

**What's the user-visible change.** Tapping the new "N reactions" strip above the reaction pills (or long-pressing any reaction pill on mobile) opens a Facebook-style sheet listing exactly who reacted, with tabs filtering by reaction type. Photos and videos both supported on iOS, Android, and web. Existing tap-to-toggle on the pills is unchanged. Strip stays hidden until at least one reaction exists, so cards with no reactions look identical to before.

**Architecture.** Two new additive GET endpoints (`GET /api/photos/{id}/reactions`, `GET /api/videos/{id}/reactions`) backed by a shared `listReactionsForMedia` helper next to the existing add/remove handlers. Authorization reuses the existing membership-gate SELECT (non-members get 404, identical to POST/DELETE). The feed enrichers (`enrichPhotoWithUrls`, `enrichVideoWithUrls`) now also return `top_reactors: ReactorAvatar[]` (up to 3 distinct most-recent reactor avatars, de-duped by user_id) via a new shared `fetchTopReactors` helper in `backend/src/shared/db/topReactors.ts` — powers the strip's avatar stack without a second round-trip. No DB migration. No infra change. No APIM policy edit.

| Phase | Status | Files |
|---|---|---|
| Backend: `ReactorEntry`, `ReactorAvatar`, `ReactorListResponse` types + `top_reactors` on `PhotoWithUrls`/`VideoWithUrls` | ✅ | `backend/src/shared/models/reaction.ts`, `backend/src/shared/models/photo.ts` |
| Backend: `getPhotoReactions` + `getVideoReactions` handlers + shared `listReactionsForMedia` | ✅ | `backend/src/functions/reactions.ts` |
| Backend: `fetchTopReactors` helper + wiring into `enrichPhotoWithUrls` + `enrichVideoWithUrls` | ✅ | `backend/src/shared/db/topReactors.ts` (new), `backend/src/functions/photos.ts`, `backend/src/functions/videos.ts` |
| Backend: 7 new jest cases (happy paths, non-member 404, empty, same-user-multi-type, avatar enrichment, null-avatar) | ✅ | `backend/src/__tests__/reactions.test.ts` (new) |
| Backend: tsc + jest 164/164 (was 157, +7 new) | ✅ | — |
| Mobile: `ReactorAvatar`, `ReactorEntry`, `ReactorList` Dart models + `topReactors` on PhotoModel/VideoModel | ✅ | `app/lib/models/reactor_model.dart` (new), `app/lib/models/photo_model.dart`, `app/lib/models/video_model.dart` |
| Mobile: `listReactions` API + `listReactors` repository on photos AND videos | ✅ | `app/lib/features/photos/data/photos_api.dart`, `app/lib/features/photos/domain/photos_repository.dart`, `app/lib/features/videos/data/videos_api.dart`, `app/lib/features/videos/domain/videos_repository.dart` |
| Mobile: `ReactorStrip` widget (avatar stack + count text, gated on totalReactions > 0) | ✅ | `app/lib/widgets/reactor_strip.dart` (new) |
| Mobile: `ReactorListSheet` (DraggableScrollableSheet + TabBar + FutureBuilder + skeleton/error/empty states) | ✅ | `app/lib/widgets/reactor_list_sheet.dart` (new) |
| Mobile: `ReactionBarWidget.onShowReactors` long-press hook (no-op when count = 0 OR callback null) | ✅ | `app/lib/features/photos/presentation/reaction_bar_widget.dart` |
| Mobile: thread strip + onShowReactors into 3 surfaces (photo card, photo detail, video card) | ✅ | `app/lib/features/photos/presentation/photo_card_widget.dart`, `app/lib/features/photos/presentation/photo_detail_screen.dart`, `app/lib/features/videos/presentation/video_card_widget.dart` |
| Mobile: 2 widget tests + flutter analyze 54-issue baseline + flutter test 70/70 | ✅ | `app/test/reactor_list_sheet_test.dart` (new) |
| Web: `ReactorAvatar`, `ReactorEntry`, `ReactorList` types + `topReactors` on `MediaBase` | ✅ | `webapp/src/models/index.ts` |
| Web: `listPhotoReactions` + `listVideoReactions` API methods | ✅ | `webapp/src/api/endpoints/photos.ts`, `webapp/src/api/endpoints/videos.ts` |
| Web: `ReactorStrip` + `ReactorListDialog` (Radix Dialog + first use of @radix-ui/react-tabs in the app) + telemetry | ✅ | `webapp/src/features/photos/ReactorStrip.tsx` (new), `webapp/src/features/photos/ReactorListDialog.tsx` (new) |
| Web: thread strip + dialog into MediaCard footer | ✅ | `webapp/src/features/photos/MediaCard.tsx` |
| Web: vite build green (2168 modules, no TS errors) | ✅ | — |
| Docs: PRD §5.8, ARCHITECTURE §6, CLAUDE.md API list, BETA_TEST_PLAN.md, this entry | ✅ | as listed |
| Backend deploy (`func azure functionapp publish func-cliquepix-fresh`) | ⏳ Pending | — |
| Web SWA deploy (auto via GH Actions on merge to `main`) | ⏳ Pending | — |
| Mobile APK build + on-device verification per BETA_TEST_PLAN §4 / §5 | ⏳ Pending | — |

**Telemetry events** (App Insights `customEvents`):
- Server: `reactor_list_fetched { mediaId, mediaType, totalReactions }` — fires on every successful GET. Replaces the need for separate client-side "viewed" events.
- Web: `web_reactor_list_viewed { mediaId, mediaType, reactionFilter, totalReactions }` — fires once per dialog open via `useEffect`. Useful for desktop-vs-mobile split.

**Deploy order:** backend (additive — old clients ignore the new endpoints and the new `top_reactors` field) → mobile + web in parallel. Old clients keep working unchanged.

**Rollback plan:** revert client commits (legacy build still works for everything except the strip). Backend endpoint can stay as harmless dead code, or be reverted independently.

**Out of scope (tracked for future):** push notifications when someone reacts to your post (would need a migration to widen `notifications.type` CHECK + FCM batching to avoid push storms during a hot event); reactor list pagination beyond 200 (sufficient at beta scale); video player screen reaction bar + strip (separate parity follow-up); reactions on DM messages (forbidden by `EVENT_DM_CHAT_ARCHITECTURE.md`).

---

## BGTask SIGABRT iOS post-auth crash — fixed (2026-05-01)

**Status:** ✅ Root cause identified via `flutter run --debug` SIGABRT capture on a tethered iPhone (iOS 26.4.1). ✅ Fix applied in `app/ios/Runner/Info.plist`. ✅ Verified on device — sign-in flow now completes cleanly, app stays foregrounded post-Safari. **Pending:** APK regression check, commit, docs propagation (this entry).

**User-visible symptom (now resolved):** every brand-new iOS user, AND any returning user who signed out + force-killed + relaunched + signed in again, saw the app "vanish" the moment Safari closed after MSAL authentication. Tapping the icon a second time landed them on Events (cached tokens already saved), so the bug was easy to work around but absolutely not shippable through App Store review (Guideline 2.1).

**Root cause:** `app/ios/Runner/Info.plist` declared

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.cliquepix.tokenRefresh</string>
</array>
```

iOS 13+ enforces a strict contract on this key: every listed identifier MUST have a corresponding `BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)` call inside `application(_:didFinishLaunchingWithOptions:)` (or earlier). CLIQUE Pix's `AppDelegate.swift` never made that call — `com.cliquepix.tokenRefresh` is consumed only by Android WorkManager (`app/lib/features/auth/domain/background_token_service.dart:18`). The instant iOS checked scheduling state for that identifier (typically when the `FlutterViewController` re-attached to the `UIWindow` after `SFSafariViewController` dismissed), iOS raised `NSInternalInconsistencyException: 'No launch handler registered for task with identifier com.cliquepix.tokenRefresh'` and the app SIGABRT'd. Release builds hide the exception message — to the user the app simply vanished.

**Why it took two debug rounds to catch:** the original `flutter run --release` build silently terminates on SIGABRT — no crash text, no stack — so prior hypothesis-driven fixes (UIAlertController-during-VC-dismiss, FCM permission post-Safari, post-frame-callback deferral, Canopy content-filter VPN) all looked equally plausible. Switching to `--debug` on a tethered device captured the actual `*** Terminating app due to uncaught exception 'NSInternalInconsistencyException'` line, which named the exact failing identifier.

| Phase | Status | Files |
|---|---|---|
| iOS Info.plist: remove `BGTaskSchedulerPermittedIdentifiers` array (replaced with explanatory comment so a future contributor doesn't re-add it) | ✅ | `app/ios/Runner/Info.plist` |
| Hygiene fix retained: post-frame deferral of FCM permission init in `_CliquePixState.build()` and of `_connectRealtime()` + Friday-reminder schedule in `AuthNotifier._startLifecycle()`. NOT the bug, but correct Flutter idiom — leaves the post-auth UI tick uncluttered. | ✅ | `app/lib/app/app.dart`, `app/lib/features/auth/presentation/auth_providers.dart` |
| `flutter analyze`: 54 issues (matches baseline; zero new errors/warnings introduced) | ✅ | — |
| `flutter test`: 68/68 pass | ✅ | — |
| Release build deployed to iPhone, sign-in repro path executed (Sign Out → close → relaunch → tap Get Started → MSAL Safari → return) — app stays open | ✅ Verified 2026-05-01 | — |
| Docs: `ARCHITECTURE.md` §5 iOS Considerations, `ENTRA_REFRESH_TOKEN_WORKAROUND.md` Known unknowns, `CLAUDE.md` iOS Info.plist + Layer 4 sections, this entry | ✅ | as listed |
| APK release build regression test (Android — confirms WorkManager Layer 4 still works for the same `com.cliquepix.tokenRefresh` identifier on its native platform) | ⏳ Pending | — |
| Commit + push | ⏳ Pending | — |

**Operational note for future maintainers:** the iOS `BGTaskScheduler` API is *not* used by CLIQUE Pix v1. Layer 4 of the 5-layer Entra refresh-token defense is Android-only (WorkManager). On iOS, equivalent coverage comes from Layer 2 (silent FCM push) + Layer 3 (foreground-resume refresh) + Layer 5 (Welcome Back). If you ever genuinely need a native iOS background-refresh task, register the launch handler in `AppDelegate.swift` BEFORE adding the identifier to `Info.plist`. The plist entry without a registered handler is an immediate-SIGABRT trap.

**Out-of-band finding:** `Firebase.initializeApp()` at `main.dart:135` logs `[core/not-initialized]` on iOS and `pushNotificationServiceProvider.initialize()` later logs `[core/no-app] No Firebase App '[DEFAULT]' has been created`. Both are caught and non-fatal (the app continues). firebase_core 4.x typically wants `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` from a `lib/firebase_options.dart` generated by `flutterfire configure`. That file does not exist in the tree; FCM is effectively disabled on iOS as a result. Fix is one-line in `main.dart` plus a `flutterfire configure` run, but it is **separate from this incident** — push notifications were already working on Android and were not the post-auth crash trigger. Tracked as a follow-up.

---

## Real-time event fan-out — `new_event` (2026-04-30)

**Status:** ✅ Code complete on local branch, ✅ migration 011 written, ✅ backend tsc + jest 157/157 green, ✅ flutter analyze 54-issue baseline preserved, ✅ flutter test 68/68 green. **Pending:** migration 011 apply to prod DB → backend deploy → on-device verification → APK build → docs commit.

**What's the user-visible win:** when a clique member creates a new Event, every other clique member sees it appear on their screen with sub-second latency when foregrounded, gets a system notification when backgrounded, and finds the event waiting in their in-app notifications list. Closing-and-reopening the app to "see" the new event is no longer needed. Reported bug filed by @user 2026-04-30 — fix delivers the requested behavior.

**Free incidental win:** the same architectural shift fixes a latent `video_ready` Web PubSub delivery bug. Pre-fix, `video_ready` only reached users on `EventFeedScreen` because the connection was per-DM-screen-only. Post-fix, all signed-in users receive `video_ready` real-time regardless of which screen they're on. No additional code change required for this fix — it's a side-effect of the connection-lifecycle promotion.

**Architecture:** copies the existing `pushVideoReady` pattern (`backend/src/functions/videos.ts:274-339`) for the dual Web PubSub + FCM + in-app notification fan-out. The new piece is making the client Web PubSub connection always-on while signed in (was previously per-DM-screen, only opened when the user navigated to a DM thread).

| Phase | Status | Files |
|---|---|---|
| Migration 011 — widen `notifications.type` CHECK constraint to include `'new_event'` | ✅ Written | `backend/src/shared/db/migrations/011_new_event_notification_type.sql` (new) |
| Backend `pushNewEvent` helper + call site in `createEvent` | ✅ | `backend/src/functions/events.ts` |
| Backend tsc + jest (157/157) | ✅ | — |
| `DmRealtimeService` — added `Stream<NewEventEvent> onNewEvent` + dispatch branch for `type: 'new_event'` | ✅ | `app/lib/features/dm/domain/dm_realtime_service.dart` |
| `RealtimeProviderInvalidator` widget — subscribes to `onNewEvent`, invalidates `allEventsListProvider` + `eventsListProvider(cliqueId)` + `notificationsListProvider`, telemetry `new_event_received` | ✅ | `app/lib/widgets/realtime_provider_invalidator.dart` (new) |
| `ShellScreen` — wraps the navigationShell in `RealtimeProviderInvalidator` so the subscription lives across all 4 bottom-tab branches and out-of-shell screens | ✅ | `app/lib/app/shell_screen.dart` |
| `AuthNotifier` — constructor injection of `DmRealtimeService` + `DmRepository`; `_connectRealtime()` 3-step dance on `_startLifecycle`; `_realtime.disconnect()` on `_stopLifecycle`; `_reconnectRealtimeIfDropped()` runs in parallel with Friday reminder via `Future.wait` on every `AppLifecycleState.resumed` | ✅ | `app/lib/features/auth/presentation/auth_providers.dart` |
| `PushNotificationService` — foreground `onMessage` invalidates events providers when `type: 'new_event'`; `_navigateFromNotification` routes `new_event` taps to `/events/{eventId}` with `new_event_tapped_fcm` telemetry | ✅ | `app/lib/services/push_notification_service.dart` |
| `notifications_screen.dart` — `case 'new_event':` in `_handleNotificationTap` routing to `/events/{eventId}`; new "New Event" icon (event_rounded, electric-aqua → deep-blue gradient) and title in `_iconAndColors` / `_title` | ✅ | `app/lib/features/notifications/presentation/notifications_screen.dart` |
| `flutter analyze`: 54 issues (matches baseline; zero new errors/warnings) | ✅ | — |
| `flutter test`: 68/68 pass (no new tests — orchestration helpers don't get unit tests in this codebase, matches `pushVideoReady` convention) | ✅ | — |
| Docs updated: PRD §5.14, ARCHITECTURE §10 + §12, NOTIFICATION_SYSTEM trigger matrix + new "New Event Real-Time Fan-Out" subsection, CLAUDE.md Push Triggers + Real-Time Feed sections, BETA_TEST_PLAN §7.1, BETA_OPERATIONS_RUNBOOK §7 with 4 new Kusto queries, this entry | ✅ | as listed |
| Migration 011 apply to `pg-cliquepixdb` (prod) | ⏳ Pending | — |
| Backend deploy `func azure functionapp publish func-cliquepix-fresh` | ⏳ Pending | — |
| Backend smoke: `POST /api/cliques/{id}/events` from a test account → confirm `new_event_push_sent` in App Insights with expected `recipientCount` | ⏳ Pending | — |
| APK release build (`flutter clean && flutter pub get && flutter build apk --release`) | ⏳ Pending | — |
| On-device verification per BETA_TEST_PLAN.md §7.1 (Samsung + iPhone, two-account scenario) | ⏳ Pending | — |

**Telemetry events** (App Insights `customEvents`):
- Server: `new_event_push_sent { eventId, cliqueId, recipientCount, webPubSubFailures, fcmFailures }`.
- Client: `new_event_received { eventId, cliqueId }`, `new_event_tapped_fcm { eventId }`, `realtime_connected { reason: 'auth_start' | 'reconnect_on_resume' }`, `realtime_connect_failed { errorCode }`, `realtime_reconnected_on_resume`.

**Deploy order (must be sequential):** migration 011 → backend → APK. Backend deploy is safe before clients update because old clients harmlessly fall through the `type:` switch on `new_event` Web PubSub messages — they keep working as before. APK ship completes the user-visible change.

**Rollback plan:** revert client commit (legacy build still works for everything except real-time event arrival). Backend `pushNewEvent` is best-effort and can be flagged off via env var `DISABLE_NEW_EVENT_PUSH=true` if a problem emerges (one-line guard at the top of the helper — TODO: add this guard if a need arises).

**No new dependencies, no new RBAC, no infrastructure change.** Reuses existing Web PubSub `wps-cliquepix-prod`, FCM credentials, and the same notifications table.

---

## Weekly Friday 5 PM local reminder (2026-04-30)

**Status:** ✅ Code complete, all tests green, release APK built (62.7 MB). On-device verification pending.

**What's live:** every signed-in user gets a recurring weekly local notification at Friday 5:00 PM in their device's local timezone — *"Evening or weekend plans? Don't forget to create an Event and assign a Clique!"* Tap routes to the Home dashboard. Mute via OS Settings → Apps → CLIQUE Pix → Notifications → Reminders channel. Multi-device-tolerant (N devices = N simultaneous fires; matches Duolingo/Strava convention).

**Architecture:** client-only via `flutter_local_notifications.zonedSchedule` with `dayOfWeekAndTime` DST-aware weekly recurrence. No backend, no migration, no FCM, no Web PubSub. The plugin auto-recurs forever after the first scheduled fire. TZ-change recovery (SFO→NYC traveler) handled by an `AppLifecycleService.onResumed` callback that re-arms the schedule when the cached IANA differs from the device's current IANA. State-machine reasons (`cold_start` / `tz_changed` / `os_purged`) drive telemetry. Full design: `docs/NOTIFICATION_SYSTEM.md` "Weekly Friday Reminder" subsection.

| Phase | Status | Files |
|---|---|---|
| New dep `flutter_timezone: ^4.0.0` (resolved 4.1.1) — required to seed `tz.local` from device IANA so DST-correct schedules fire at the right wall-clock | ✅ | `app/pubspec.yaml`, `app/pubspec.lock` |
| `FridayReminderService` — schedule/cancel/state-machine + IANA fallback + `pendingNotificationRequests()` cache check | ✅ | `app/lib/services/friday_reminder_service.dart` (new) |
| `main.dart` — seeds `tz.setLocalLocation` after `tz.initializeTimeZones`; creates second Android channel `cliquepix_reminders` (default importance) alongside `cliquepix_default` | ✅ | `app/lib/main.dart` |
| `PushNotificationService` — `friday_reminder` tap branch → `router.go('/events')` + `friday_reminder_tapped` telemetry; placed before existing event_id/clique_id fallbacks | ✅ | `app/lib/services/push_notification_service.dart` |
| `AuthNotifier._startLifecycle` — schedules the reminder fire-and-forget on `AuthAuthenticated`; `_stopLifecycle` cancels on sign-out / delete-account | ✅ | `app/lib/features/auth/presentation/auth_providers.dart` |
| `AppLifecycleService` — gains `onResumed` callback (auth-independent) so the reminder reschedules on every resume without coupling to the token-refresh path | ✅ | `app/lib/features/auth/domain/app_lifecycle_service.dart` |
| Unit tests — 16 new tests covering `computeNextFriday5pm` across all weekdays + DST spring-forward, `computeReason` state machine, `flutter_timezone` failure fallback, no-op skip path | ✅ | `app/test/friday_reminder_service_test.dart` (new) |
| `flutter analyze`: 54 issues (matches pre-change baseline; zero new errors/warnings) | ✅ | — |
| `flutter test`: 68/68 pass (incl. the 16 new) | ✅ | — |
| Release APK build (`flutter clean && flutter pub get && flutter build apk --release`) | ✅ | `app/build/app/outputs/flutter-apk/app-release.apk` (62.7 MB, +0.2 MB vs. 2026-04-29 baseline) |
| Docs: `PRD.md` §5.14, `ARCHITECTURE.md` §10 + §20 telemetry, `NOTIFICATION_SYSTEM.md` trigger matrix + new "Weekly Friday Reminder" subsection, `CLAUDE.md` Frontend deps + Notification Architecture, `BETA_TEST_PLAN.md`, `BETA_OPERATIONS_RUNBOOK.md` Kusto queries | ✅ | as listed |
| On-device verification (Samsung + iPhone — see `BETA_TEST_PLAN.md` §13 / Friday reminder rows) | ⏳ Pending | — |

**Telemetry events** (visible in App Insights `customEvents`): `friday_reminder_scheduled` { iana, next_fire_at, reason }, `friday_reminder_skipped_tz_unchanged`, `friday_reminder_tz_lookup_failed`, `friday_reminder_tapped`.

**Caught during implementation (DST bug):** `TZDateTime.add(Duration(days: 7))` adds 168 absolute hours, not 7 calendar days — across DST that silently shifts by ±1 hour. Fixed by switching to calendar-day arithmetic via the `TZDateTime` constructor's overflow-day handling (`tz.TZDateTime(loc, n.year, n.month, n.day + 7, 17)`). Caught by the `DST spring-forward` unit test before any device ever ran the code.

**No backend deploy required.** No DB migration. No APIM policy change. No Azure infra change. No web client change (CLAUDE.md: "no Web Push in v1"). Pure mobile feature.

**Operational note:** if a future developer wonders "can we use `zonedSchedule` for X?" — the rule is in `CLAUDE.md`'s Notification Architecture section: **`zonedSchedule` is permitted ONLY for displaying static recurring reminders, never for executing code.** The previous Layer-2 token-refresh `zonedSchedule` was deleted because that primitive does not run code at fire time. The Friday reminder is the only such notification in v1 and the architectural template for any future reminder type.

---

## Earlier history

(Last updated before reminder: 2026-04-29 — APIM Product-scope rate-limit + quota removed from "starter" — fifth and (finally) actual root cause of the recurring upload 429; client silent-retry safety net added)

## APIM Product-scope `rate-limit` + `quota` removal — incident #5 (2026-04-29)

**Status:** ✅ APIM "starter" product policy cleaned in production; ✅ 429 metric alert wired; ✅ client-side silent-retry shipped to repo (APK build pending).

**What changed and why.** A brand-new test user hit HTTP 429 on their FIRST upload attempt with the body `{statusCode: 429, message: "Rate limit is exceeded. Try again in 38 seconds."}`. The 2026-04-27 cleanup had only addressed the **API**-scope policy. APIM has FOUR policy scopes (Global → Product → API → Operation). A Phase 0+A audit found APIM's **default starter Product policy** — created automatically when the service was first provisioned and never touched — still contained `<rate-limit calls="5" renewal-period="60" />` AND `<quota calls="100" renewal-period="604800" />` (5/min + 100/week). New users auto-subscribed to the `starter` product hit the 5/min cap during their first auth-verify + list-events + list-cliques + get-upload-url chain.

| Change | Status | Files |
|---|---|---|
| APIM `starter` product policy: PUT clean `<base />`-only policy. Removed both `<rate-limit>` and `<quota>` | ✅ Deployed 2026-04-29 via `az rest PUT` | (live APIM service) |
| APIM `unlimited` product: confirmed already had no policy (404) | ✅ No-op | — |
| APIM Global scope: confirmed already empty | ✅ No-op | — |
| APIM Operation scope (all 7 operations): confirmed no policies (404) | ✅ No-op | — |
| `apim_policy.xml`: in-file comment now warns about ALL FOUR scopes (was API-scope-only); incident #5 added to history | ✅ | `apim_policy.xml` |
| Azure Monitor metric alert `apim-429-detected` (count Requests > 0 where GatewayResponseCode includes 429, 5-min window, 1-min eval) | ✅ Created 2026-04-29 | (Azure Monitor) |
| New utility `silentRetryOn429<T>` — wraps a Future-returning call with one-shot 429 silent retry, honors Retry-After header (capped 60s), per-device 5-min cooldown via SharedPreferences | ✅ | `app/lib/core/utils/upload_url_silent_retry.dart` |
| Photo upload: `camera_capture_screen` wraps `getUploadUrl` with silent retry. User sees no error banner on first 429 — just a slightly longer "Getting upload URL..." progress phase. Telemetry: `photo_upload_url_429_silenced` / `_silent_retry_succeeded` / `_silent_retry_failed` | ✅ | `app/lib/features/photos/presentation/camera_capture_screen.dart` |
| Video upload: `VideosRepository.uploadVideo` accepts an optional `wrapGetUploadUrl` callback so the screen can supply silent-retry without coupling the repo to telemetry/SharedPreferences. `video_upload_screen` passes `silentRetryOn429`. Same telemetry shape with `video_*` prefix | ✅ | `app/lib/features/videos/domain/videos_repository.dart`, `app/lib/features/videos/presentation/video_upload_screen.dart` |
| `flutter analyze`: 54 issues (matches pre-change baseline; zero new errors/warnings) | ✅ | — |
| Release APK build (`flutter clean && flutter pub get && flutter build apk --release`) | ⏳ Pending | `app/build/app/outputs/flutter-apk/app-release.apk` |
| On-device verification (affected test user retries upload) | ⏳ Pending | — |

**Backup of prior live policies:** `C:\Users\genew\AppData\Local\Temp\apim-bak-20260429-1432\` — contains `global.xml`, `api.xml`, `product-starter.xml` (with the 5/min + 100/week rules), `product-starter-after.xml` (the clean replacement), and `product-clean.json` (the body used in the PUT).

**Operational note for future maintainers:**
- When an APIM 429 alert fires, run the Phase 0+A audit script in `docs/BETA_OPERATIONS_RUNBOOK.md` §2 BEFORE anything else. It enumerates all four scopes; the clean state is "no flagged files."
- Do NOT re-add `<rate-limit>`, `<rate-limit-by-key>`, or `<quota>` at ANY scope until APIM is migrated to Standard v2 (distributed cache + SLA). The 5-incident history in `apim_policy.xml`'s in-file comment is canonical.
- The client-side `silentRetryOn429` is a safety net, not a substitute for the APIM cleanup. It silences ONE 429 per 5-min window per device; a sixth incident with sustained 429s would still surface to users.

---



## Organizer media moderation — `canDeleteMedia` (2026-04-28)

**Status:** ✅ backend deployed to prod; ✅ release APK built (62.5 MB). Web SWA deploy pending merge to `main`. On-device verification (Samsung + iPhone) pending.

**What changed and why.** Until now, only the uploader could delete a photo or video. If a clique member uploaded inappropriate content into an event and refused to remove it, the event organizer had no recourse short of deleting the entire event (which destroyed everyone else's content). The new authorization model accepts EITHER the uploader OR the event organizer (`events.created_by_user_id`) on `DELETE /api/photos/{id}` and `DELETE /api/videos/{id}`. Random clique members continue to receive HTTP 403. Uploader takes precedence when both apply, so an organizer deleting their own upload is logged as a self-delete.

| Phase | Files | Status |
|---|---|---|
| Backend: `canDeleteMedia` helper + 8 unit tests | `backend/src/shared/utils/permissions.ts`, `backend/src/__tests__/permissions.test.ts` | ✅ |
| Backend: `deletePhoto` enriched SELECT (JOIN events) + role-aware telemetry | `backend/src/functions/photos.ts:488-548` | ✅ |
| Backend: `deleteVideo` enriched SELECT + role-aware telemetry (no `status` filter preserved) | `backend/src/functions/videos.ts:758-810` | ✅ |
| Backend: tsc green | — | ✅ |
| Backend: jest 157/157 green (was 149 before; +8 new) | — | ✅ |
| Mobile: shared `deleteDialogCopy` helper for self-vs-organizer copy | `app/lib/widgets/confirm_destructive_dialog.dart` | ✅ |
| Mobile: `MediaOwnerMenu` rename `isOwner→canDelete`; `isOrganizerDeletingOthers` prop drives Remove vs Delete copy | `app/lib/widgets/media_owner_menu.dart` | ✅ |
| Mobile: `PhotoCardWidget` + `VideoCardWidget` accept `eventCreatedByUserId`; compute `canDelete = isUploader \|\| isOrganizerDeletingOthers` | `app/lib/features/photos/presentation/photo_card_widget.dart`, `app/lib/features/videos/presentation/video_card_widget.dart` | ✅ |
| Mobile: `EventFeedScreen` threads `eventCreatedByUserId` from `EventDetailScreen` | `app/lib/features/photos/presentation/event_feed_screen.dart`, `app/lib/features/events/presentation/event_detail_screen.dart` | ✅ |
| Mobile: `PhotoDetailScreen` + `VideoPlayerScreen` watch `eventDetailProvider`, gate Delete on `canDelete`, branch dialog body | `app/lib/features/photos/presentation/photo_detail_screen.dart`, `app/lib/features/videos/presentation/video_player_screen.dart` | ✅ |
| Mobile: `flutter analyze` 54 issues (was 55; same pre-existing baseline; zero new errors/warnings introduced) | — | ✅ |
| Web: `MediaCard` accepts `eventCreatedByUserId`; computes `canDelete`; branches `<ConfirmDestructive>` copy + success toast | `webapp/src/features/photos/MediaCard.tsx` | ✅ |
| Web: `MediaFeed` + `EventDetailScreen` thread the prop | `webapp/src/features/photos/MediaFeed.tsx`, `webapp/src/features/events/EventDetailScreen.tsx` | ✅ |
| Web: `vite build` green (2164 modules, bundle budget intact) | — | ✅ |
| Docs: PRD §5.2 + ARCHITECTURE §6 + CLAUDE.md Security Rules + BETA_TEST_PLAN §4/§5/§12.5 + this file | as listed | ✅ |
| Backend deploy (`func azure functionapp publish func-cliquepix-fresh`) | — | ✅ Deployed 2026-04-28 — health endpoints 200 via direct (`func-cliquepix-fresh.azurewebsites.net`) AND Front Door (`api.clique-pix.com`) |
| Release APK built (`flutter clean && flutter pub get && flutter build apk --release`) | `app/build/app/outputs/flutter-apk/app-release.apk` (62.5 MB) | ✅ Built 2026-04-28 |
| Mobile on-device verification (Samsung + iPhone, 3-account scenario per `BETA_TEST_PLAN.md` §4 + §5) | — | ⏳ Pending |
| Web SWA deploy (auto via GH Actions on merge to `main`) | — | ⏳ Pending |
| App Insights: organizer-abuse alert wired (Kusto query B in plan) | — | ⏳ Pending |

**Telemetry shape change (additive — backward compatible):**
- `photo_deleted` / `video_deleted` gain three new dimensions: `deleterRole` ∈ `'uploader' | 'organizer'`, `uploaderId` (UUID or `''` if account deleted), `eventOrganizerId` (UUID or `''` if account deleted)
- `userId` (the deleter) remains unchanged
- Existing Kusto queries continue to function; new queries can filter on `tostring(customDimensions.deleterRole) == "organizer"` for moderation auditing

**Deploy order:** backend → mobile + web (parallel). Backend first is safe because pre-existing clients ignore the new capability (the menu just stays hidden for organizers). Once backend is live, organizers gain the ability via mobile/web ship.

**No DB migration.** `events.created_by_user_id` already exists. The handler enriches its SELECT with a JOIN against `events`. No schema change.

**Operational note:** Both `events.created_by_user_id` and `photos.uploaded_by_user_id` are nullable since migration 004 (ON DELETE SET NULL on user account deletion). The `canDeleteMedia` helper guards against nullable comparisons; if both IDs are null no one can delete the media (the cleanup timer reaps it on event expiry — correct behavior).

**Out of scope (future):** notifying the original uploader when an organizer removes their content; extending moderation to clique owners; bulk moderation tools; appeals workflow.

---

## APIM rate-limit removal + client traffic reduction (2026-04-27)

**Status:** APIM policy deployed (no rate-limit-by-key on any path); client APK built with WorkManager + polling + retry-interceptor fixes.

**What changed and why.** Four consecutive user-blocking 429 incidents from APIM `rate-limit-by-key` on the Developer-tier (single in-memory cache, no SLA) made the gateway-side rate limit a net negative for beta. Each fix attempt — bumping 120 → 300 → 600/min, adding bypass paths, versioning the counter cache key with `v2:` prefix — produced a *new* 429 within minutes. Removing the policy entirely is the only foolproof guarantee that uploads will never 429. Abuse protection now lives at the application layer (JWT auth, event-membership checks, User Delegation SAS expiry, orphan cleanup timer).

| Change | Status | Files |
|---|---|---|
| APIM policy: removed `<rate-limit-by-key>` (both global 600/min + avatar sub-limit). Kept `<base />` + `<cors>`. | ✅ Deployed 2026-04-27 via `az rest PUT` | `apim_policy.xml` (with full incident-history comment) |
| Flutter: `RetryInterceptor` never retries 429s; honors `Retry-After` header (capped 30s); `maxRetries: 3 → 1` to reduce amplification on connection errors | ✅ | `app/lib/services/retry_interceptor.dart` |
| Flutter: WorkManager `existingWorkPolicy: replace → keep` + 4-hour `wm_last_run_at_ms` SharedPreferences guard inside `callbackDispatcher` (telemetry confirmed it was firing 6×/min instead of 1×/8h) | ✅ | `app/lib/features/auth/domain/background_token_service.dart` |
| Flutter: new `LifecycleAwarePollerMixin` — pauses 30 s polling timers when app is paused/inactive/hidden, restarts (with one-shot refresh) on resume | ✅ | `app/lib/core/utils/lifecycle_aware_poller_mixin.dart` |
| Flutter: adopted by `event_feed_screen`, `cliques_list_screen`, `clique_detail_screen` | ✅ | as listed |
| Flutter: `camera_capture_screen` enriched 429 handler — parses `Retry-After`, shows live "Wait Ns" countdown on retry button + Upload button (disabled during cooldown), expandable "Show details" diagnostic panel covering Dio type / status / body / runtime type | ✅ | `app/lib/features/photos/presentation/camera_capture_screen.dart` |
| Avatar crop UX fix — dark `UCropTheme` + `hideBottomControls: true` + first-time `_showCropHint` AlertDialog (gated on `avatar_crop_hint_shown` SharedPreferences key) | ✅ | `app/android/app/src/main/res/values/styles.xml`, `AndroidManifest.xml`, `avatar_repository.dart`, `avatar_editor_screen.dart` |

**Deploy artifacts:** `app/build/app/outputs/flutter-apk/app-release.apk` (62.5 MB, debug-signed). Backend not redeployed — APIM is gateway-only.

**Operational note for future maintainers:** do **not** re-add `rate-limit-by-key` to `apim_policy.xml` until APIM is migrated off the Developer tier. The policy file's in-line comment lists the four-incident history reproducibly. Standard v2 has a distributed rate-limit cache and an SLA — the right place to revisit gateway-side rate limiting.

---

## Avatars v1 — Profile Pictures (2026-04-24)

**Status:** backend deployed to prod, web + mobile pending ship.

**What's live:**
- Migration 009 (silent-push activity tracking) + Migration 010 (avatars) applied to `pg-cliquepixdb`
- Backend deployed to `func-cliquepix-fresh` — health endpoint 200 via Function App URL AND `api.clique-pix.com` (Front Door → APIM path)
- All 5 avatar endpoints registered: `POST /api/users/me/avatar/upload-url`, `POST /api/users/me/avatar` (confirm), `DELETE /api/users/me/avatar`, `PATCH /api/users/me/avatar/frame`, `POST /api/users/me/avatar-prompt`
- Azure Blob CORS verified — `https://clique-pix.com` + `http://localhost:5173` allowed on `GET`, `PUT`, `HEAD`, `OPTIONS` with 1h preflight cache

**Verified before cutover:**
- Backend 149/149 tests green (134 existing + 15 new `avatarEnricher` tests)
- `npm run build` (tsc) green — 5 pre-deploy type errors caught and fixed (trackEvent number→string, PhotoWithUrls/VideoWithUrls avatar fields, events enricher index signature)
- Flutter analyze 55 issues (was 61, all remaining pre-existing info-level lints; no errors/warnings introduced by avatar work)
- Web `vite build` green — 2164 modules transformed, no TypeScript errors, bundle budget intact (initial JS ≤ 400 KB / 137 KB gzip)

**Pending:**

Adds user-uploadable headshots that replace the initials-in-a-gradient-ring fallback everywhere (Profile hero, photo/video feed cards, clique member lists, DM threads + chat headers). Brand-new users see a branded welcome prompt on first sign-in — three choices (Yes / Maybe Later / No Thanks) with server-persisted state so the decision survives reinstall and is honored across mobile + web.

| Phase | Status | Files |
|---|---|---|
| Migration 010 (`avatar_blob_path`, `avatar_thumb_blob_path`, `avatar_updated_at`, `avatar_frame_preset`, `avatar_prompt_dismissed`, `avatar_prompt_snoozed_until`) | ✅ Applied 2026-04-24 | `backend/src/shared/db/migrations/010_user_avatars.sql` |
| Backend: `avatarEnricher.ts` + `buildAuthUserResponse` + `shouldPromptForAvatar` | ✅ Code done + 15 unit tests | `backend/src/shared/services/avatarEnricher.ts`, `backend/src/__tests__/avatarEnricher.test.ts` |
| Backend: `avatars.ts` — 5 endpoints (upload-url / confirm / delete / frame / avatar-prompt) | ✅ | `backend/src/functions/avatars.ts` |
| Backend: `authMiddleware` SELECT adds avatar columns; `authVerify` + `getMe` emit enriched shape incl. `should_prompt_for_avatar`; `deleteMe` cleans avatar blobs | ✅ | `backend/src/shared/middleware/authMiddleware.ts`, `backend/src/functions/auth.ts` |
| Backend: 14 handler propagation (photos, videos, events, cliques, dm) with `enrichUserAvatar` helper | ✅ | `backend/src/functions/{photos,videos,events,cliques,dm}.ts` |
| ~~Backend: APIM per-IP 10/min sub-limit on avatar sub-paths~~ — superseded by 2026-04-27 rate-limit removal (above) | ✅ then ❌ removed | `apim_policy.xml` |
| Flutter: `AvatarWidget` extended (thumbUrl / framePreset / cacheKey, size-aware URL selection) | ✅ | `app/lib/widgets/avatar_widget.dart` |
| Flutter: `UserModel` + 5 response models carry avatar denorm fields | ✅ | `app/lib/models/*.dart` |
| Flutter: avatar feature (api, repo, picker sheet, editor, welcome prompt, animated empty-state, first-visit hint) | ✅ | `app/lib/features/profile/**` |
| Flutter: `image_cropper` + `confetti` added to pubspec; UCropActivity declared in AndroidManifest | ✅ | `app/pubspec.yaml`, `app/android/app/src/main/AndroidManifest.xml` |
| Flutter: `AuthNotifier.updateUserAvatar` (pure state swap, no token refresh) | ✅ | `app/lib/features/auth/presentation/auth_providers.dart` |
| Flutter: 5 AvatarWidget call sites threaded (photo_card, video_card, dm_thread_list, dm_chat, local_pending_video) | ✅ | as listed |
| Flutter: Profile screen tappable avatar + welcome prompt on Home initState | ✅ | `app/lib/features/profile/presentation/profile_screen.dart`, `app/lib/features/home/presentation/home_screen.dart` |
| Web: `Avatar.tsx` extended with imageUrl / thumbUrl / framePreset / cacheBuster | ✅ | `webapp/src/components/Avatar.tsx` |
| Web: `AvatarEditor` (react-easy-crop + filter/frame) + `AvatarWelcomePromptModal` + `AvatarWelcomePromptGate` + `useAvatarUpload` hook | ✅ | `webapp/src/features/profile/**` |
| Web: `ProfileScreen` tappable avatar with confetti on first upload | ✅ | `webapp/src/features/profile/ProfileScreen.tsx` |
| Web: `MediaCard` passes uploader avatar fields to Avatar | ✅ | `webapp/src/features/photos/MediaCard.tsx` |
| Web: `react-easy-crop` + `canvas-confetti` added to package.json | ✅ | `webapp/package.json` |
| Docs | ✅ | `docs/PRD.md` §5.13, `docs/ARCHITECTURE.md` users table + blob paths, `docs/CLAUDE.md` avatar pipeline, `docs/BETA_TEST_PLAN.md` §10, `docs/WEB_CLIENT_ARCHITECTURE.md` avatar section, this file |
| Backend deploy (`func azure functionapp publish func-cliquepix-fresh`) | ✅ Shipped 2026-04-24 | 45 functions deployed (was 40 pre-avatar) |
| Azure Blob CORS verification (`GET`+`PUT` from `clique-pix.com`) | ✅ Verified 2026-04-24 | Already configured from event-media playback rollout; no change needed |
| Web client deploy (auto-deploys from `main` via GH Actions → SWA) | ⏳ Pending `main` merge | See `.github/workflows/swa-deploy.yml` |
| Mobile APK build + on-device verification (Samsung + iPhone) | ⏳ Not started | See BETA_TEST_PLAN.md §10 (13 new avatar test rows) |

Deploy order executed: migration 009 → migration 010 → backend → (CORS verified) → web + mobile pending ship. Legacy mobile clients ignore the new response fields and keep rendering initials — no version lockstep required.


## Entra Refresh-Token Defense — Silent Push Edition (2026-04-19)

**Status:** backend shipped 2026-04-24 alongside Avatars v1 (Migration 009 + the `avatarEnricher`/avatar endpoints deployed in the same `func publish`). Client-side silent-push plumbing is code-complete on `main` but hasn't been rolled out via a mobile build yet — on-device verification per `ENTRA_REFRESH_TOKEN_WORKAROUND.md` "Verifying in production" is still pending.

Re-architected the 5-layer Entra External ID 12-hour refresh-token defense after an audit revealed every service was dead code — `AuthRepository` took `alarmRefreshService` and `backgroundTokenService` as optional constructor params and `authRepositoryProvider` never supplied them, so every `?.` callsite was a silent no-op. `AppLifecycleService` and `BatteryOptimizationService` were never instantiated; `WelcomeBackDialog.show()` had no caller; `BackgroundTokenService.callbackDispatcher` was a `TODO` that always returned `true` without calling MSAL; `main.dart:85` filtered the `TOKEN_REFRESH_TRIGGER` notification payload but never triggered a refresh. The original Layer 2 (`flutter_local_notifications.zonedSchedule`) was architecturally flawed — it only displays a notification, it does not execute code; silent `Importance.min` notifications the user never tapped refreshed nothing.

Replaced Layer 2 with server-triggered silent FCM data pushes (Microsoft's own documented pattern in Azure Communication Services → "Solution 2: Remote Notification"):

| Layer | Mechanism | Change |
|---|---|---|
| 1 | Battery-optimization exemption | Wired — called from `HomeScreen.initState` |
| 2 | **Server silent push** (NEW) | `refreshTokenPushTimer` (backend) + `_firebaseMessagingBackgroundHandler` (client) |
| 3 | Foreground refresh on resume | Wired — `AppLifecycleService.start()` called on `AuthAuthenticated`, `stop()` on sign-out |
| 4 | WorkManager (Android) | Real MSAL refresh in isolate now implemented (no more `TODO`) |
| 5 | Welcome Back dialog | New `AuthReloginRequired` state; `LoginScreen` shows `WelcomeBackDialog` via `ref.listen`; `checkAuthStatus` routes cold-start after 12h to this path |

| Phase | Status | Files |
|---|---|---|
| Migration 009 (`last_activity_at` + `last_refresh_push_sent_at`) | ✅ Applied 2026-04-24 | `backend/src/shared/db/migrations/009_user_activity_tracking.sql` |
| Backend: `authMiddleware` last-activity write + `verifyJwtAllowExpired` | ✅ Code done | `backend/src/shared/middleware/authMiddleware.ts` |
| Backend: `fcmService` silent-push support (`FcmMessage.silent`, `sendSilentToMultipleTokens`) | ✅ Code done + 7 unit tests | `backend/src/shared/services/fcmService.ts`, `backend/src/__tests__/fcmService.test.ts` |
| Backend: `refreshTokenPushTimer` (CRON `0 7,22,37,52 * * * *`) | ✅ Code done | `backend/src/functions/timers.ts` |
| Backend: `POST /api/telemetry/auth` endpoint | ✅ Code done | `backend/src/functions/telemetry.ts` |
| Client: `MsalConstants` extracted (isolate-safe MSAL config) | ✅ | `app/lib/core/constants/msal_constants.dart` |
| Client: `AuthReloginRequired` state + `checkAuthStatus` cold-start recovery | ✅ | `app/lib/features/auth/domain/auth_state.dart`, `auth_providers.dart` |
| Client: `AuthRepository` rewired — `alarmRefreshService` deleted, `refreshTokenDetailed()` added | ✅ | `app/lib/features/auth/domain/auth_repository.dart` |
| Client: `BackgroundTokenService.callbackDispatcher` — real MSAL refresh in isolate | ✅ | `app/lib/features/auth/domain/background_token_service.dart` |
| Client: `AppLifecycleService` — `pending_refresh_on_next_resume` flag + telemetry | ✅ | `app/lib/features/auth/domain/app_lifecycle_service.dart` |
| Client: wiring in `auth_providers.dart` — every service now instantiated | ✅ | `app/lib/features/auth/presentation/auth_providers.dart` |
| Client: `_firebaseMessagingBackgroundHandler` silent-push handler | ✅ | `app/lib/main.dart` |
| Client: `PushNotificationService` foreground `type: 'token_refresh'` branch | ✅ | `app/lib/services/push_notification_service.dart` |
| Client: `TelemetryService` (Dio + SharedPreferences ring buffer + isolate drain) | ✅ | `app/lib/services/telemetry_service.dart` |
| Client: Battery-exempt dialog wired in `HomeScreen.initState` | ✅ | `app/lib/features/home/presentation/home_screen.dart` |
| Client: Token Diagnostics screen + tap-7-times unlock in Profile | ✅ | `app/lib/features/profile/presentation/token_diagnostics_screen.dart`, `profile_screen.dart` |
| Client: Dead file deleted | ✅ | `app/lib/features/auth/domain/alarm_refresh_service.dart` removed |
| Docs | ✅ | `docs/ENTRA_REFRESH_TOKEN_WORKAROUND.md` rewritten, `CLAUDE.md` §"Entra External ID — Known Bug" updated, this file, `docs/BETA_OPERATIONS_RUNBOOK.md` troubleshooting section added |
| On-device verification (Samsung + iPhone) | ⏳ Not started | See test plan in ENTRA_REFRESH_TOKEN_WORKAROUND §Verifying in production |

Deploy order: migration 009 → backend → client. Backend silent-push path must be live before clients start enforcing the new flow.

## Video v1 Status

## Video v1 Status

**Branch:** `feature/video` — ready for on-device verification, pending merge to `main`

| Phase | Status | Commit |
|---|---|---|
| 1. Database migration (007 — media_type + video columns) | ✅ Applied to production | `fe3e69f` |
| 2. Infrastructure (Log Analytics, ACR Standard, Container Apps Environment+Job, Storage Queue, RBAC, Budget) | ✅ Provisioned in `rg-cliquepix-prod` | `8e569ab`, `343d893` |
| 3. Transcoder container (Dockerfile + Node.js runner + FFmpeg) | ✅ v0.1.2 deployed to `cracliquepix.azurecr.io` | `a6a9930`, `9db5bad` |
| 4. Backend Function endpoints (10 new routes) | ✅ Deployed to `func-cliquepix-fresh` | `552cb60`, `9db5bad` |
| 5. Backend integration test (E2E with real test video) | ✅ All 3 attempts passed after 2 bugs fixed | `9db5bad` |
| 6. Flutter frontend (11 new files, 11 modified) | ✅ Compiles, debug APK builds successfully | `45f5baf` |
| 7. Polish + on-device testing + merge to main | ⏳ In progress — manual testing required before merge | — |

**See also:**
- `docs/VIDEO_ARCHITECTURE_DECISIONS.md` — 8 architecture decisions + 7 product Q&A
- `docs/VIDEO_INFRASTRUCTURE_RUNBOOK.md` — Azure resources runbook (as-built)
- `docs/CliquePix_Video_Feature_Spec.md` — original generic feature spec
- `docs/VIDEO_V1_TESTING_CHECKLIST.md` — manual on-device testing checklist (Phase 7)

---

## Pre-existing v1 Status (photos, cliques, events, DMs)

### Backend (Azure Functions v4 TypeScript)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (package.json, tsconfig, host.json) | Done | |
| Database schema (001_initial_schema.sql) | Done | 8 tables, indexes, triggers |
| Migration (002_member_joined_notification.sql) | Done | Added `member_joined` to notifications type CHECK constraint (run 2026-03-31) |
| Migration (003_event_deleted_notification.sql) | Done | Added `event_deleted` to notifications type CHECK constraint (run 2026-04-03) |
| Migration (004_user_delete_set_null.sql) | Done | Made `created_by_user_id` / `uploaded_by_user_id` nullable with ON DELETE SET NULL (run 2026-04-03) |
| Shared models (8 files) | Done | User, Clique, Event, Photo, Reaction, Notification, PushToken |
| Shared utils (response, errors, validators) | Done | |
| Shared services (db, blob, sas, fcm, telemetry) | Done | Code reviewed + 49 issues fixed |
| Auth middleware (JWT via JWKS) | Done | Uses typed errors (UnauthorizedError, NotFoundError) |
| Error handler middleware | Done | Correlation IDs via invocationId |
| Auth functions (verify, getMe, deleteMe) | Done | `deleteMe` cleans up blobs, sole-owner cliques, user record |
| Cliques functions (8 endpoints) | Done | joinClique sends FCM push; `removeMember` endpoint for owner to remove members |
| Events functions (4 endpoints) | Done | Includes `deleteEvent` for organizer-initiated deletion |
| Photos functions (5 endpoints) | Done | Validates via blob properties, async thumbnail gen |
| Reactions functions (2 endpoints) | Done | Static imports, consistent telemetry keys |
| Notifications functions (5 endpoints) | Done | Includes `deleteNotification` and `clearNotifications` |
| Timer functions (3 timers) | Done | Deduplication on expiring notifications |
| Health endpoint | Done | Standard response envelope |
| npm dependencies installed | Done | |

### Flutter Mobile App (Dart)

| Component | Status | Notes |
|-----------|--------|-------|
| Project scaffold (pubspec.yaml, analysis_options) | Done | Flutter 3.35.5, Dart 3.9.2 |
| Native scaffolding (Android/iOS) | Done | `flutter create` with org `com.cliquepix`; Android package `com.cliquepix.clique_pix`, iOS bundle ID `com.cliquepix.app` (changed from flutter create default `com.cliquepix.cliquePix`) |
| Design system (colors, gradients, typography, theme) | Done | Dark theme throughout, uses `withValues(alpha:)` (Flutter 3.27+) |
| Constants (endpoints, app constants, environment) | Done | Domain: `clique-pix.com` |
| Error types (sealed AppFailure, error mapper) | Done | |
| Routing (GoRouter with shell route) | Done | Event-first flow, 4 tabs (Home/Cliques/Notifications/Profile), auth guard with redirect preservation for invite deep links |
| API client (Dio + 3 interceptors) | Done | Auth interceptor uses parent Dio for retry |
| Token storage service | Done | Refresh callback mechanism wired to MSAL |
| Storage service (save to gallery + share + batch download) | Done | Single photo/video save, unified batch download (photos + videos) with progress, share via temp file |
| Deep link service | Done | Host: clique-pix.com, initialized in app.dart via ConsumerStatefulWidget |
| Push notification service | Done | FCM token registration + refresh; foreground display via `flutter_local_notifications`; background/terminated tap navigation; static callback for local notification taps |
| Shared widgets (7 widgets) | Done | Gradient-ringed avatars, dark-themed bottom nav with gradient icons |
| Data models (5 models) | Done | PhotoModel with resilient num/string parsing, EventModel with cliqueName/memberCount |
| Auth feature (MSAL integration) | Done | `msal_auth` 3.3.0, custom API scope, auto-login on startup, MSAL error recovery, dismiss button |
| 5-layer token refresh defense | Done | All layers wired; loginHint threaded through Layer 5 |
| Cliques feature (API, repository, providers, 6 screens) | Done | Dark theme, gradient-bordered cards, gradient-ringed avatars, full-width "Create Clique" gradient pill above the list (mirrors Home's `_buildCreateEventCTA` pattern; replaced the prior bare `+` IconButton on 2026-05-05 — see top entry), pull-to-refresh + 30s polling on list and detail screens, JoinCliqueScreen with dark theme |
| Events feature (API, repository, providers, 4 screens) | Done | Event-first flow, events home screen, dark-themed event detail with hero header, labeled "Create Event" FAB, `listAllEvents` backend endpoint, event cards show photo + video counts, `Wrap`-based layout handles large system font sizes without overflow |
| Photos feature (API, repository, services, providers, 6 screens/widgets) | Done | `pro_image_editor` for crop/draw/stickers/filters, prominent "Upload to Event" button, step-by-step progress overlay, `uploaded_by_name` in responses, multi-select photo download with progress, debug logging throughout pipeline |
| Notifications feature (API, repository, providers, 1 screen) | Done | Dark theme, colored icon badges, unread/read styling, `member_joined` type with clique navigation |
| Profile feature (1 screen) | Done | Dark theme, gradient profile card, grouped settings with gradient icons, Privacy Policy + Terms of Service open `clique-pix.com` in-app browser via `url_launcher` |
| App entry point (main.dart) | Done | Firebase, timezone, WorkManager, local notifications plugin (top-level), `cliquepix_default` channel creation, Android 13+ permission request, FCM `onMessage` foreground listener, background message handler |
| All API providers wired to ApiClient | Done | No UnimplementedError providers |
| App launcher icon | Done | CLIQUE Pix camera logo at all Android densities |
| Login screen | Done | Dark gradient, animated glowing logo, slide-in animations |
| App-wide dark theme | Done | `AppTheme.dark` applied globally in app.dart; all screens use consistent dark (#0E1525) background with gradient accents |
| Home screen dashboard | Done | State-aware: brand new, has cliques, active events, expired events; How It Works card, clique quick-start chips, active event cards with countdown timers |
| Android manifest | Done | Permissions, App Links, FCM, MSAL BrowserTabActivity |
| iOS Info.plist | Done | Camera/photo permissions, background modes, MSAL URL schemes |
| Firebase config (Android) | Done | `google-services.json` placed in `android/app/` |
| Firebase config (iOS) | Done | `GoogleService-Info.plist` placed in `ios/Runner/` |

### Website (clique-pix.com)

| Component | Status | Notes |
|-----------|--------|-------|
| Landing page (index.html) | Done | Brand design, feature highlights, download CTAs |
| Privacy policy (privacy.html) | Done | Photo + video + DM coverage, 14 sections, Xtend-AI LLC, NC jurisdiction, effective April 13, 2026 |
| Terms of service (terms.html) | Done | Photo + video + DM coverage, 16 sections, effective April 13, 2026 |
| Invite landing page (invite.html) | Done | Dark-themed, platform detection, intent:// for Android, app store buttons, OG meta tags |
| Static Web App config | Done | MIME types for well-known files, security headers, `/invite/*` rewrite to invite.html |
| Well-known files | Done | apple-app-site-association (Team ID: `4ML27KY869`) + assetlinks.json (debug SHA256 fingerprint) |
| Azure Static Web App | Done | `swa-cliquepix-prod`, Free tier, redeployed 2026-03-31 |
| Custom domains | Done | `clique-pix.com` (apex) + `www.clique-pix.com`, managed SSL |

### Documentation

| Component | Status | Notes |
|-----------|--------|-------|
| .gitignore | Done | Firebase admin SDK key pattern added |
| ARCHITECTURE.md | Done | Domain corrected to clique-pix.com |
| PRD.md | Done | |
| CLAUDE.md | Done | Domain corrected, PostgreSQL updated to pg-cliquepixdb |
| ENTRA_REFRESH_TOKEN_WORKAROUND.md | Done | |

---

## Azure Infrastructure Status

### All Resources (in `rg-cliquepix-prod`)

| Resource | Name | Location | Status |
|----------|------|----------|--------|
| Resource Group | `rg-cliquepix-prod` | eastus | Ready |
| Log Analytics | `log-cliquepix-prod` | eastus | Ready |
| Application Insights | `appi-cliquepix-prod` | eastus | Ready (workspace-based) |
| Function App | `func-cliquepix-fresh` | eastus | Ready — 39 functions deployed (incl. 7 DM endpoints) |
| Storage Account | `stcliquepixprod` | eastus | Ready — `photos` container, blob public access disabled |
| PostgreSQL | `pg-cliquepixdb` | eastus2 | Ready — v18, `cliquepix` DB with 10 tables (incl. `event_dm_threads`, `event_dm_messages`) |
| Key Vault | `kv-cliquepix-prod` | eastus | Ready — `pg-connection-string` + `fcm-credentials` + `web-pubsub-connection-string` stored |
| API Management | `apim-cliquepix-003` | eastus | Ready — **Basic v2 SKU** (since 2026-05-05; migrated from Developer-tier `apim-cliquepix-002` which was decommissioned the same day). 99.95% SLA, autoscale 1→10 units, $150/month. **NO rate-limit-by-key** (see 6-incident history in `apim_policy.xml`); CORS is the only inbound policy. API-scope policy is loaded from `apim_policy.xml` via Bicep `loadTextContent` (single source of truth) |
| Front Door | `fd-cliquepix-prod` | global | Ready — Standard SKU (no WAF) |
| Static Web App | `swa-cliquepix-prod` | eastus2 | Ready — clique-pix.com + www |
| DNS Zone | `clique-pix.com` | global | Ready — api CNAME, apex ALIAS, www CNAME, TXT validation |
| Web PubSub | `wps-cliquepix-prod` | eastus | Ready — Standard S1, hub: `cliquepix` |
| Entra External ID | `cliquepix.onmicrosoft.com` | — | Ready — app registered, 3 identity providers |

### Deleted Resources

| Resource | Name | Reason |
|----------|------|--------|
| PostgreSQL | `pg-cliquepix` | Replaced by `pg-cliquepixdb` (v18) |
| API Management | `apim-cliquepix-002` | Replaced by `apim-cliquepix-003` (Basic v2) on 2026-05-05. Name locked by Azure for ~30 days per policy. |

### RBAC Role Assignments (Function App managed identity)

| Role | Scope | Status |
|------|-------|--------|
| Storage Blob Data Contributor | `stcliquepixprod` | Assigned |
| Storage Blob Delegator | `stcliquepixprod` | Assigned |
| Key Vault Secrets User | `kv-cliquepix-prod` | Assigned |

### Traffic Path (verified working)

```
Flutter App → Front Door (fd-cliquepix-prod) → APIM (apim-cliquepix-003, Basic v2) → Azure Functions (func-cliquepix-fresh) → PostgreSQL / Blob Storage
```

Health endpoint confirmed at:
- `https://func-cliquepix-fresh.azurewebsites.net/api/health`
- `https://apim-cliquepix-003.azure-api.net/api/health`
- `https://cliquepix-api-fcc6b7f4enathbac.z02.azurefd.net/api/health`
- `https://api.clique-pix.com/api/health`

### APIM Rate Limiting Policies

| Scope | Limit | Operation |
|-------|-------|-----------|
| Global (all operations) | 60 requests/min per IP | API-level policy |
| Upload URL | 10 requests/min per IP | `POST /events/{eventId}/photos/upload-url` |
| Auth verify | 5 requests/min per IP | `POST /auth/verify` |

### Function App Settings

| Setting | Value | Source |
|---------|-------|--------|
| `PG_CONNECTION_STRING` | Key Vault reference | `kv-cliquepix-prod/pg-connection-string` |
| `FCM_CREDENTIALS` | Key Vault reference | `kv-cliquepix-prod/fcm-credentials` |
| `STORAGE_ACCOUNT_NAME` | `stcliquepixprod` | Direct |
| `ENTRA_TENANT_ID` | `27748e01-d49f-4f0b-b78f-b97c16be69dc` | Direct (CIAM tenant) |
| `ENTRA_CLIENT_ID` | `7db01206-135b-4a34-a4d5-2622d1a888bf` | Direct |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | App Insights connection string | Direct |
| `NODE_ENV` | `production` | Direct |

### Entra External ID Configuration

| Component | Status | Details |
|-----------|--------|---------|
| CIAM Tenant | `cliquepix.onmicrosoft.com` | Tenant ID: `27748e01-d49f-4f0b-b78f-b97c16be69dc` |
| App Registration | `CLIQUE Pix` | Client ID: `7db01206-135b-4a34-a4d5-2622d1a888bf` |
| Redirect URI (Android debug) | Configured | `msauth://com.cliquepix.clique_pix/W28%2BgAaZ9fNu1yL%2FGMRe94rK0dY%3D` |
| Redirect URI (iOS) | Configured | `msauth.com.cliquepix.app://auth` (auto-generated from Bundle ID `com.cliquepix.app`) |
| Application ID URI | Configured | `api://7db01206-135b-4a34-a4d5-2622d1a888bf` |
| Exposed API Scope | Configured | `access_as_user` — required for MSAL to return app-scoped access token |
| Email + Password | Enabled | Primary local sign-in (changed from Email OTP on 2026-05-06; existing OTP users preserved per Microsoft documented behavior — see velvety-kindling-dragon plan) |
| Google Identity Provider | Configured | OAuth client via Google Cloud Console |
| Apple Identity Provider | Configured | Service ID: `com.cliquepix.app.service`, Key ID: `4NYXZNV9VD` |
| User Flow | `SignUpSignIn` | Email + Password + Google + Apple, CLIQUE Pix app associated |

### Firebase Configuration

| Component | Status | Details |
|-----------|--------|---------|
| Firebase Project | `CLIQUE Pix` | Project ID: `clique-pix-d7fde` |
| Cloud Messaging (FCM) | Enabled | V1 API |
| Android app | Registered | Package: `com.cliquepix.clique_pix` |
| iOS app | Registered | Bundle ID: `com.cliquepix.app` |
| Service account key | Stored | Key Vault: `kv-cliquepix-prod/fcm-credentials` |
| google-services.json | Placed | `app/android/app/google-services.json` (gitignored) |
| GoogleService-Info.plist | Placed | `app/ios/Runner/GoogleService-Info.plist` (gitignored) |

### Google OAuth Configuration

| Component | Status | Details |
|-----------|--------|---------|
| Google Cloud Project | `CLIQUE Pix` | |
| OAuth consent screen | Configured | External, Testing mode |
| Authorized domains | Set | `ciamlogin.com`, `microsoftonline.com`, `clique-pix.com` |
| OAuth client | Web application | For Entra federation (server-to-server) |
| App domain URLs | Set | Home: `https://clique-pix.com`, Privacy: `/privacy.html`, Terms: `/terms.html` |

### Apple Sign In Configuration

| Component | Status | Details |
|-----------|--------|---------|
| App ID | `com.cliquepix.app` | Team ID: `4ML27KY869` |
| Services ID | `com.cliquepix.app.service` | Sign In with Apple configured with CIAM domains |
| Key | `CliquePix Sign In` | Key ID: `4NYXZNV9VD` |
| Client secret (.p8) | Active | **Renewal required: September 2026** |

### Configuration Notes

| Setting | Value | Notes |
|---------|-------|-------|
| `allowSharedKeyAccess` | `true` | Required by Azure Functions runtime for AzureWebJobsStorage |
| `allowBlobPublicAccess` | `false` | No anonymous blob access |
| Storage SKU | `Standard_GZRS` | Changed from RAGZRS (not supported by Consumption plan) |
| Function App plan | Consumption (Linux) | EastUSLinuxDynamicPlan |
| Deployment method | Run-from-package (blob SAS) | Windows→Linux zip requires Python zipfile for forward slashes |
| Front Door endpoint | `cliquepix-api-fcc6b7f4enathbac.z02.azurefd.net` | |
| Custom domain (API) | `api.clique-pix.com` | CNAME → Front Door, managed certificate |
| Custom domain (website) | `clique-pix.com` + `www.clique-pix.com` | ALIAS/CNAME → Static Web App |
| Android package name | `com.cliquepix.clique_pix` | Generated by `flutter create --org com.cliquepix` |
| iOS bundle ID | `com.cliquepix.app` | |
| MSAL package | `msal_auth: ^3.3.0` | Replaced `msal_flutter` (v1 embedding incompatible with Flutter 3.35) |
| MSAL scopes | `['api://7db01206.../access_as_user']` | Custom API scope only; OIDC scopes added implicitly by MSAL |
| CIAM issuer format | `https://{tenantId}.ciamlogin.com/{tenantId}/v2.0` | Tenant ID as subdomain (NOT tenant name) |
| CIAM JWKS URI | `https://cliquepix.ciamlogin.com/{tenantId}/discovery/v2.0/keys` | Tenant name as subdomain |
| API base URL (dev + prod) | `https://api.clique-pix.com` | Front Door custom domain; `fd-cliquepix-prod.azurefd.net` is NOT a valid hostname |

---

## Code Review Summary (2026-03-25)

49 issues found and fixed across 7 commits:

| Severity | Count | Examples |
|----------|-------|---------|
| Critical | 13 | Blob path prefix, SAS permissions, TLS validation, telemetry init, auth wiring |
| High | 18 | Missing telemetry events, image compression, blob upload streaming, reaction IDs |
| Medium | 12 | Feed polling, notification dedup, error interceptor, HEIC detection |
| Low | 5 | Health envelope, deprecated withOpacity, correlation IDs, barrel exports |

---

## Authentication Fix Summary (2026-03-26)

Four bugs were found and fixed in the MSAL → Backend authentication chain:

| Bug | Problem | Fix |
|-----|---------|-----|
| 1. No custom API scope | MSAL returned a Microsoft Graph token (wrong signing keys) when only OIDC scopes were requested | Exposed `api://clientId/access_as_user` scope in Entra; MSAL now requests only this scope |
| 2. Backend issuer mismatch | Backend validated issuer as `cliquepix.ciamlogin.com/...` but CIAM tokens use `{tenantId}.ciamlogin.com/...` | Changed issuer to `https://${TENANT_ID}.ciamlogin.com/${TENANT_ID}/v2.0` |
| 3. Wrong dev API base URL | `fd-cliquepix-prod.azurefd.net` returns 404 (Azure resource name, not actual endpoint) | Changed to `api.clique-pix.com` for both dev and prod |
| 4. `offline_access` declined | CIAM tenants decline `offline_access` without admin consent | Removed from scopes; MSAL handles refresh tokens internally |

**Key learning:** For Entra External ID (CIAM), a mobile app calling a custom backend API **must** expose an API scope (`Expose an API` → `Add a scope`). Without it, `result.accessToken` is a Microsoft Graph token signed by Graph keys — not the CIAM tenant's keys — causing `invalid signature` on backend verification. OIDC scopes (`openid`, `profile`, `email`) must NOT be requested explicitly; MSAL adds them implicitly. Mixing API scopes with OIDC scopes causes `MsalDeclinedScopeException`.

---

## Photo Upload Pipeline Fix Summary (2026-03-26)

The photo upload pipeline appeared completely broken — photos never appeared after capture. Root cause: a **double-pop navigation bug** in the ProImageEditor v5.1.4 integration.

| Bug | Problem | Fix |
|-----|---------|-----|
| 1. ProImageEditor double-pop | v5.x's `doneEditing()` calls `onImageEditingComplete` then immediately calls `onCloseEditor`. Having `Navigator.pop()` in both callbacks double-popped: removed editor + CameraCaptureScreen. User never saw the preview/Upload button. | Moved `Navigator.pop()` to `onCloseEditor` only; `onImageEditingComplete` saves bytes to closure variable without popping |
| 2. BlobUploadService Dio config | `Content-Type` set in headers map instead of `Options.contentType`; manual `Content-Length` could conflict with Dio auto-calc; no `responseType: ResponseType.bytes` for Azure XML errors | Set `contentType: 'image/jpeg'` on Options, `responseType: ResponseType.bytes`, removed manual Content-Length |

**Key learning:** ProImageEditor v5.x's `doneEditing()` (main_editor.dart:1514-1566) always calls `onCloseEditor` after `onImageEditingComplete` completes. The correct pattern is: save data in `onImageEditingComplete` (no pop), then pop in `onCloseEditor`. This matches the official Firebase/Supabase example in the ProImageEditor package.

---

## QR Invite Flow Fix + Clique Join Notifications (2026-03-31)

### Problem 1: QR Code invite returns 404

Scanning a clique invite QR code navigated to `https://clique-pix.com/invite/{code}` which returned a 404 from Azure because the Static Web App had no route or page for `/invite/*` paths.

**Root causes and fixes:**

| Issue | Fix |
|-------|-----|
| No web page for `/invite/*` paths | Created `website/invite.html` — branded dark-themed landing page with platform detection, `intent://` URI for Android, app store buttons |
| No SWA rewrite rule | Added `/invite/*` → `invite.html` rewrite in `staticwebapp.config.json` (must come before `.well-known` routes) |
| `DeepLinkService` never initialized | Converted `app.dart` to `ConsumerStatefulWidget`, call `initialize(router)` in `initState` |
| Invite route bypassed auth check | Removed `isInviteRoute` exemption from GoRouter redirect; added `?redirect=` query param to preserve invite URL through login flow |
| `.well-known` placeholders | Replaced `TEAM_ID` → `4ML27KY869` in AASA; replaced SHA256 placeholder with debug keystore fingerprint in assetlinks.json |
| `JoinCliqueScreen` light theme | Restyled with dark background, gradient heading, aqua accents, dark TextField |

**Website redeployed** to `swa-cliquepix-prod` via SWA CLI. Invite URLs now return 200 with branded page.

### Problem 2: Owner not notified when someone joins clique

| Issue | Fix |
|-------|-----|
| No `member_joined` notification type | Created migration `002_member_joined_notification.sql` — ALTERed CHECK constraint on `notifications.type` |
| Backend didn't send push on join | Added FCM push + notification record creation to `joinClique()` in `cliques.ts`; replicates exact pattern from `photos.ts` |
| `NotificationType` model missing type | Added `'member_joined'` to union type in `notification.ts` |
| Client didn't render `member_joined` | Added icon/color case (person_add + aqua/violet), title case ("New Member"), and clique navigation in `_NotificationTile.onTap` |
| No FCM token registration | Created `PushNotificationService` — requests permission, gets FCM token, sends to `POST /api/push-tokens`, listens for token refresh |
| No auto-refresh on clique screens | Added `WidgetsBindingObserver` + `RefreshIndicator` + `Timer.periodic(30s)` polling to both `CliquesListScreen` and `CliqueDetailScreen` |

**Backend redeployed** to `func-cliquepix-fresh`. Migration run against `pg-cliquepixdb`.

**Known issue:** Push notifications not yet confirmed working end-to-end on device. FCM token registration and backend push logic are implemented but need further debugging.

### Problem 3: Global light theme overriding dark screens

`app.dart` used `AppTheme.light` — a Material 3 light theme that overrode per-widget dark styling on some screens (notably `CreateCliqueScreen`).

**Fix:** Created `AppTheme.dark` in `app_theme.dart` with dark defaults matching the app's visual design (dark scaffold, dark AppBar, dark InputDecoration, aqua accents). Switched `app.dart` to `theme: AppTheme.dark`.

---

## Remaining Tasks

### Completed

| Task | Status | Notes |
|------|--------|-------|
| MSAL authentication flow | Done | End-to-end working: MSAL → custom API scope → backend JWT verification → user upsert |
| Event-first UX flow | Done | 4 tabs (Events/Cliques/Notifications/Profile), event creation with inline clique picker |
| Dark theme across all screens | Done | Cliques detail, event detail, camera capture, notifications, profile — all consistent |
| Photo editor integration | Done | `pro_image_editor` ^5.1.4 — crop, draw, stickers, emoji, filters, text |
| Auth error recovery | Done | Auto-login on startup, MSAL cache reset on failure, error dismiss button |
| New app icon/logo | Done | Generated via `flutter_launcher_icons` from 1024x1024 source |
| Backend: `listAllEvents` endpoint | Done | `GET /api/events` — returns all events across user's cliques with clique name/member count |
| Backend: `uploaded_by_name` in photos | Done | `listPhotos` JOINs users table; `PhotoWithUrls` includes uploader display name |
| PhotoModel resilient parsing | Done | Handles PostgreSQL bigint-as-string (file_size_bytes) without type cast errors |
| ProImageEditor double-pop fix | Done | v5.x calls `onCloseEditor` after `onImageEditingComplete`; moved `Navigator.pop()` to `onCloseEditor` only to prevent double-pop that skipped preview/upload screen |
| BlobUploadService Dio fix | Done | Set `contentType` on Options (not in headers), `responseType: ResponseType.bytes`, removed manual Content-Length |
| Upload pipeline debug logging | Done | `[CliquePix]` prefixed `debugPrint` at every step for `adb logcat` diagnosis |

### Recently Completed (2026-03-31)

| Task | Status | Notes |
|------|--------|-------|
| Well-known files: real values | Done | Apple Team ID `4ML27KY869` in AASA, debug SHA256 in assetlinks.json |
| Invite landing page | Done | `website/invite.html` with SWA rewrite rule, deployed to `swa-cliquepix-prod` |
| Deep link service initialization | Done | `DeepLinkService.initialize(router)` called in `app.dart` |
| Auth gate for invite routes | Done | Unauthenticated invite URLs redirect to login with `?redirect=` preservation |
| Global dark theme | Done | Created `AppTheme.dark`, switched `app.dart` from `AppTheme.light` |
| Home screen dashboard | Done | 4-state contextual dashboard, How It Works card, clique chips, active event cards |
| Back buttons on full-screen routes | Done | Event detail, camera capture, photo detail all have explicit back navigation |
| Clique join push notification (backend) | Done | `joinClique()` sends FCM to existing members, creates `member_joined` notification records |
| DB migration: member_joined type | Done | `002_member_joined_notification.sql` run against `pg-cliquepixdb` |
| FCM token registration (client) | Done | `PushNotificationService` gets token, registers with backend, listens for refresh |
| Clique screens refresh | Done | Pull-to-refresh + app-resume + 30s polling on CliquesListScreen and CliqueDetailScreen |
| JoinCliqueScreen dark theme | Done | Gradient heading, aqua accents, dark TextField |
| Dark theme consistency | Done | EventsListScreen, CreateCliqueScreen, InviteScreen all restyled |

### Recently Completed (2026-04-01)

| Task | Status | Notes |
|------|--------|-------|
| Clique member management: owner remove | Done | `DELETE /api/cliques/{cliqueId}/members/{userId}` — owner-only, validates role, prevents self-removal |
| Clique member management: leave/delete UI | Done | "Leave Clique" button (members), "Delete Clique" button (sole owner), confirmation dialogs |
| Clique member management: tappable removal | Done | Owner sees remove icon on non-owner members; tap shows confirmation dialog |
| Graceful 404 on member removal | Done | When removed user's screen refreshes, detects 404 DioException and navigates to `/cliques` with SnackBar instead of showing error |
| State invalidation: member count | Done | Uses `membersAsync.valueOrNull?.length` for live count; avoids full-screen loading flash |
| Frontend API: `removeMember` | Done | Endpoint constant, CliquesApi method, CliquesRepository method |
| Push notification: foreground display | Done | `onMessage` listener in `main.dart` shows heads-up banner via `flutter_local_notifications.show()` |
| Push notification: channel creation | Done | `cliquepix_default` channel with `Importance.high` created in `main.dart` at startup |
| Push notification: Android 13+ permission | Done | `requestNotificationsPermission()` via Android-specific plugin API |
| Push notification: background tap | Done | `onMessageOpenedApp` → navigates to clique/event via GoRouter |
| Push notification: terminated tap | Done | `getInitialMessage()` → delayed navigation after router init |
| Push notification: local tap routing | Done | Static callback bridges `main.dart` `onDidReceiveNotificationResponse` → `PushNotificationService.onNotificationTap` → GoRouter |
| Push notification: in-app list refresh | Done | `onMessage` invalidates `notificationsListProvider` for immediate update |
| Backend redeployed | Done | `func azure functionapp publish func-cliquepix-fresh` — 27 functions |

### Recently Completed (2026-04-04)

| Task | Status | Notes |
|------|--------|-------|
| Post-creation invite flow | Done | When creating event with NEW clique, modal bottom sheet prompts "Invite Friends" or "Skip for Now" on Event Detail screen. Uses `GoRouter.extra` to pass cliqueId/cliqueName (one-time, not restorable from URL) |
| Top-level routes for cross-shell navigation | Done | Added `/view-clique/:cliqueId` and `/invite-to-clique/:cliqueId` outside `StatefulShellRoute` — fixes back-navigation when pushing to shell-internal routes from Event Detail |
| Clique navigation from event detail | Done | AppBar group icon (always visible) + tappable clique name with chevron in hero section — both use top-level `/view-clique/` route for clean back-navigation |

### Recently Completed (2026-04-03)

| Task | Status | Notes |
|------|--------|-------|
| Event deletion: backend endpoint | Done | `DELETE /api/events/{eventId}` — creator-only auth, blob cleanup before cascade DB delete, push + in-app notification to clique members |
| Event deletion: frontend UI | Done | Delete icon in AppBar (organizer only), dark-themed confirmation dialog, post-delete navigation to events list with SnackBar |
| Event deletion: API/repository layer | Done | `deleteEvent()` method in EventsApi and EventsRepository |
| Photo card name readability fix | Done | Uploader name and timestamp text overridden to white for dark card background (#162033) — was invisible dark navy (#0F172A) |
| Multi-select media download: selection state | Done | `MediaSelectionNotifier` + `mediaSelectionProvider` (family by eventId) in photos_providers.dart — unified for photos + videos |
| Multi-select media download: card UI | Done | Circular checkbox overlay on photo and video cards (aqua when selected), tap toggles selection; processing/failed videos excluded from selection |
| Multi-select media download: feed UI | Done | Selection toolbar with Select All / Deselect All + Cancel; download action bar with dynamic label ("Download 3 Photos" / "Download 2 Videos" / "Download 5 Items") |
| Multi-select media download: batch save | Done | Photos via `savePhotoToGallery()`, videos via `saveVideoToGallery()` (MP4 fallback URL) — sequential with combined progress, continues past individual failures |
| Backend redeployed | Done | `func azure functionapp publish func-cliquepix-fresh` — 28 functions |
| Clique screens: refresh button | Done | Refresh icon in AppBar on both CliqueDetailScreen and CliquesListScreen — calls existing `_refresh()` / `cliquesListProvider.notifier.refresh()` |
| DB migration: `event_deleted` notification type | Done | Migration `003_event_deleted_notification.sql` — added `event_deleted` to notifications CHECK constraint |
| Event creator name: backend queries | Done | `getEvent`, `listEvents`, `listAllEvents` now JOIN `users` table, return `created_by_name` |
| Event creator name: frontend model | Done | Added `createdByName` optional field to `EventModel`, parsed from `created_by_name` |
| Event creator name: UI display | Done | "Created by {name}" row with person icon in event detail hero header |
| Backend redeployed (2nd) | Done | `func azure functionapp publish func-cliquepix-fresh` — 28 functions |
| Notification clear/delete: backend endpoints | Done | `DELETE /api/notifications/{id}` (single) + `DELETE /api/notifications` (clear all) with ownership verification |
| Notification clear/delete: API/repository | Done | `deleteNotification()` + `clearAll()` in notifications_api.dart and notifications_repository.dart |
| Notification clear/delete: UI | Done | Clear All icon in AppBar with confirmation dialog; swipe-to-dismiss (Dismissible) on each notification tile |
| Backend redeployed (3rd) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — 31 functions |
| Copy user ID button | Done | User ID displayed on profile card with copy icon, copies to clipboard with SnackBar |
| Delete account: backend endpoint | Done | `DELETE /api/users/me` — cleans up sole-owner cliques + blobs, deletes user photos + blobs, deletes user record |
| Delete account: DB migration 004 | Done | `created_by_user_id` and `uploaded_by_user_id` made nullable with ON DELETE SET NULL on cliques, events, photos |
| Delete account: auth layer | Done | `deleteAccount()` threaded through AuthApi → AuthRepository → AuthNotifier with local cleanup |
| Delete account: profile UI | Done | Red "Delete Account" tile with confirmation dialog; GoRouter auto-redirects to login on success |
| Backend redeployed (4th) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — 32 functions |
| DM: Azure Web PubSub provisioned | Done | `wps-cliquepix-prod` Standard S1, connection string in Key Vault, Function App setting configured |
| DM: database migration 005 | Done | `event_dm_threads` + `event_dm_messages` tables with indexes, CHECK constraints, CASCADE from events |
| DM: Web PubSub service | Done | `webPubSubService.ts` — token negotiation, `sendToUser` for direct user-targeted delivery (switched from thread-scoped groups) |
| DM: backend endpoints (7) | Done | createOrGetThread, listThreads, getThread, listMessages, sendMessage (rate limited), markRead, negotiate |
| DM: backend models | Done | `dmThread.ts` — DmThread + DmMessage TypeScript interfaces |
| DM: timer integration | Done | DM threads marked read-only in `cleanupExpired` timer, then hard-deleted with event via CASCADE |
| DM: clique removal integration | Done | `removeMember` + `leaveClique` mark affected DM threads as read-only |
| DM: Flutter models | Done | `DmThreadModel` + `DmMessageModel` with fromJson factories |
| DM: Flutter API + repository | Done | `dm_api.dart` + `dm_repository.dart` — 7 methods matching backend |
| DM: Flutter realtime service | Done | `dm_realtime_service.dart` — WebSocket connection with auto-reconnect (exponential backoff), re-negotiates fresh URL on reconnect |
| DM: Flutter providers + routing | Done | Riverpod providers, 3 routes under `/events/:eventId/` (dm-threads, dm/new, dm/:threadId) |
| DM: thread list screen | Done | Dark-themed list with unread indicators, "New Message" FAB, empty state |
| DM: chat screen | Done | Message bubbles (gradient for sent, dark for received), composer, read-only banner |
| DM: member picker screen | Done | Lists clique members for starting new DMs |
| DM: event detail entry points | Done | Messages icon in AppBar + prominent "Messages" button below "Add Photo" |
| DM: FCM push tap routing | Done | `dm_message` type navigates to `/events/{eventId}/dm/{threadId}` |
| DM: debug logging | Done | `[CliquePix DM]` logs for eventId, API response, thread count |
| Backend redeployed (5th) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — 39 functions |
| Fix: Sign out not working | Done | Missing `await`, unprotected cleanup, stale PCA instance — all three fixed with defense-in-depth (try/catch + try/finally + `_pca = null`) |
| Fix: Welcome screen UI | Done | Hide redundant FAB in brand-new state, brighten helper text (0.3→0.55), "Add Your Crew"→"Add Your Clique" |
| Fix: DM real-time delivery | Done | Switched from group-based (`sendToAll`) to user-targeted (`sendToUser`) delivery; fixed WebSocket reconnection to re-negotiate fresh URL |
| Backend redeployed (6th) | Done | `func azure functionapp publish func-cliquepix-fresh --force` — DM sendToUser fix |
| Fix: Sign-out browser session | Done | Added `browser_sign_out_enabled: true` to `msal_config.json` + `Prompt.login` on `acquireToken` — clears Google session cookies on sign-out, forces re-authentication on sign-in |

### Recently Completed (2026-04-13)

| Task | Status | Notes |
|------|--------|-------|
| Fix: iOS MSAL auth loop | Done | Three root causes: (1) no iOS platform registered in Azure Entra, (2) Info.plist URL scheme `msauth.com.cliquepix.app` didn't match bundle ID, (3) missing keychain entitlements (`com.microsoft.adalcache`). Errors were silently swallowed by `auth_providers.dart` catch block. |
| iOS bundle ID reconciliation | Done | Changed Xcode bundle ID from `com.cliquepix.cliquePix` (flutter create default) to `com.cliquepix.app` to match Apple App ID, Firebase iOS, and Apple Sign In config. Updated Azure Entra iOS platform accordingly. |
| Info.plist URL scheme fix | Done | Changed from hardcoded `msauth.com.cliquepix.app` to `msauth.$(PRODUCT_BUNDLE_IDENTIFIER)` — auto-resolves at build time |
| Runner.entitlements created | Done | Keychain group `$(AppIdentifierPrefix)com.microsoft.adalcache` for MSAL token caching |
| iOS deployment target bump | Done | 13.0 → 15.0 (required by `firebase_core` v4 and `workmanager_apple`) |
| Firebase packages upgraded | Done | `firebase_core` 2.x → 4.7.0, `firebase_messaging` 14.x → 16.2.0 (old versions incompatible with Xcode 26.2), `share_plus` 9.x → 12.x (dependency conflict with new firebase_core) |
| iOS code signing configured | Done | `DEVELOPMENT_TEAM = 4ML27KY869`, `CODE_SIGN_STYLE = Automatic` on all Runner build configs |
| iOS on-device verification | Done | App builds, installs, and authenticates successfully on physical iPhone (iOS 26.3.1) |

### Recently Completed (2026-04-15)

| Task | Status | Notes |
|------|--------|-------|
| Profile: remove "View Licenses" from About dialog | Done | Replaced Flutter's built-in `showAboutDialog()` (which always injects a VIEW LICENSES button) with a custom `showDialog` + `AlertDialog` containing only a Close action. Title, version, and legalese text preserved. `profile_screen.dart:145-166` |
| Cliques list: remove "+ Create Clique" FAB | Done | Deleted the always-visible gradient FAB from `CliquesListScreen` to eliminate duplication with the empty-state card's "Create Clique" button. Reduced list bottom padding from 100 → 24 now that the FAB no longer needs clearance. Users with existing cliques still reach Create Clique via the Home tab's "+ New Clique" quick-start chip. `cliques_list_screen.dart:135` |
| Event Detail: add 4-tab bottom nav | Done | Event Detail (`/events/:eventId`) previously had no way to jump directly to Home / Cliques / Notifications / Profile — only a back arrow. Extracted the shell's nav bar into a shared `AppBottomNav` widget (`app/lib/widgets/app_bottom_nav.dart`), refactored `ShellScreen` to use it (pixel-identical), and added `bottomNavigationBar: AppBottomNav(...)` to `EventDetailScreen`'s Scaffold. Taps use `context.go('/events' \| '/cliques' \| '/notifications' \| '/profile')` — go_router's `StatefulShellRoute` activates the correct branch cleanly. `selectedIndex: 0` (Home highlighted) since events live under `/events`. Zero routing changes, zero cross-branch push concerns. Full-screen children (camera, photo detail, video capture/upload/player, DM list/chat) remain without the nav. Rejected alternative of moving `/events/:eventId` into the Home shell branch due to go_router 14 cross-branch `push` ambiguity from `events_list_screen.dart:137` and notification tap handlers. `event_detail_screen.dart:29-62`, `shell_screen.dart`, `app_bottom_nav.dart` (new) |
| Profile: reorder legal tiles, add Contact Us | Done | First settings group reordered to `About CLIQUE Pix → Terms of Service → Privacy Policy → Contact Us`. Gradient pairs reassigned so the brand rainbow cascade still flows top-to-bottom (aqua→deep, deep→violet, violet→pink, pink→aqua). New Contact Us tile opens a dark-themed dialog (matching Sign Out / Delete Account styling) showing `support@xtend-ai.com` in a `SelectableText` with two actions: **Copy Email** (Clipboard + "Email copied!" floating snackbar, mirroring the existing user-ID copy pattern) and **Send Email** (launches `mailto:support@xtend-ai.com?subject=Clique%20Pix%20Support` via `LaunchMode.externalApplication`). File-level `_supportEmail` const prevents typo drift across the three use sites. Android manifest `<queries>` block extended with `SENDTO` + `mailto` intent — **required** for Android 11+ package visibility, else `launchUrl` silently no-ops. iOS `LSApplicationQueriesSchemes` left unchanged (non-blocking since `canLaunchUrl` is not used). `profile_screen.dart:8,141-237`, `AndroidManifest.xml:98-111`. |
| Photo upload: fix 403 AuthorizationFailure + add client error mapper | Done (pending deploy) | **Regression fix:** commit `8d8decf` (2026-03-24, "backend critical fixes C1-C7") removed `permissions.create = true` from `generateUploadSas`, leaving only `write`. Azure Blob Storage's User Delegation SAS requires `create` for Put Blob against a brand-new path (per Microsoft's own docs: "Write a new blob" is listed under the Create permission). Videos were unaffected because Put Block only needs `write`. Restored both `write` and `create` on upload SAS to match pre-regression baseline and Microsoft's canonical `acdrw` CLI upload template. **Client diagnostic improvements:** new `BlobUploadFailure` typed exception in `blob_upload_service.dart` parses Azure's XML error envelope (`<Code>`, `<Message>`) via regex. `CameraCaptureScreen._friendlyError` maps Azure codes (`AuthorizationFailure`, `AuthenticationFailed`, `InvalidHeaderValue`, `RequestBodyTooLarge`), Dio timeouts, and backend HTTP statuses (401/403/404/5xx) to user-facing text; raw exceptions only surface in `kDebugMode`. Backend: `sasService.ts:43-48`. Client: `blob_upload_service.dart`, `camera_capture_screen.dart:117-171`. Deploy sequence: backend first (resolves existing clients immediately), client changes ship in next app build. |
| Home screen: remove "+ Create Event" FAB | Done | Parallel to the earlier Cliques list FAB removal (c11f208). Deleted `_buildFab()` and the Scaffold `floatingActionButton:` wiring from `home_screen.dart`; also removed the now-orphaned `homeState` build-scope computation. The `hasActiveEvents` state previously had **no** centered Create Event CTA and relied solely on the FAB, so added a new `_buildCreateEventCTA('Start Another Event')` below the active event cards to preserve the Home-tab Create Event path for users with existing events. Reduced three `SliverPadding` bottoms from `100` → `24` (FAB clearance no longer needed), matching the `c11f208` pattern. Label choice "Start Another Event" distinguishes from "Create Event" (zero-state), "Create Your First Event" (first-timer), and "Start a New Event" (re-engagement). `home_screen.dart:85-95, 357-375, 428-432`. |

### Recently Completed (2026-04-22)

| Task | Status | Notes |
|------|--------|-------|
| Branded "CLIQUE Pix" header on all four tab screens | Done | App name was not visible anywhere inside the running app — only the per-screen title ("Home" / "My Cliques" / "Notifications" / "Profile") appeared. Added a persistent brand ribbon (rounded 56 × 56 logo from `assets/logo.png` with a soft aqua glow + "CLIQUE Pix" wordmark in `AppGradients.primary` via `ShaderMask`, 40 px w700) above each screen title. **New widget:** `app/lib/widgets/branded_sliver_app_bar.dart` — reusable `BrandedSliverAppBar` owns the `SliverAppBar` shell (`pinned: true`, `expandedHeight: 260`), per-tab accent wash (electric aqua / deep blue / violet / pink), wordmark positioned via `SafeArea` + `Padding(top: 80)` + `Align.topCenter` inside `flexibleSpace` so it sits as a hero element, and the existing screen title anchored 16 px from the bottom of the expanded area. Accepts `screenTitle`, `screenTitleGradient`, `accentColor`, `accentOpacity`, `actions`. **Trade-off:** wordmark scrolls away with the header hero on content scroll — collapsed state is just a 56 px dark bar with actions (Refresh on Cliques, Clear All on Notifications when non-empty). The brand wordmark is intentionally the same across all four tabs for identity consistency; the existing per-screen title gradients (Notifications deepBlue→violet, Profile violet→pink) are preserved. **Applied to:** `home_screen.dart:119-151`, `cliques_list_screen.dart:65-104`, `notifications_screen.dart:61-103`, `profile_screen.dart:25-59` — each ~35 lines of inline `SliverAppBar` code collapsed into a single `BrandedSliverAppBar(...)` call. Iterated on sizing (28 → 56 px logo, 20 → 40 px text) and vertical position (`toolbarHeight` approach → `flexibleSpace`-positioned hero) across three user feedback rounds. `flutter analyze` on the new widget is green; overall baseline unchanged. |

### Recently Completed (2026-04-17)

| Task | Status | Notes |
|------|--------|-------|
| Video card emoji reactions + `ReactionBarWidget` refactor | Done | Video cards were the only remaining v1 feature area missing the ❤️ 😂 🔥 😮 reaction row — all backend plumbing (routes, shared handler branching on `media_type`, `enrichVideoWithUrls` returning `reaction_counts` + `user_reactions`, `VideosRepository.addReaction/removeReaction`, `VideoModel.reactionCounts/userReactions`) already existed; only the Flutter UI was missing. Decoupled `ReactionBarWidget` from `photosRepositoryProvider` (was hardcoded at line 41) by parameterizing with `onAdd` + `onRemove` async callbacks — widget is now media-agnostic (`mediaId` param, no Riverpod coupling, converted `ConsumerStatefulWidget` → `StatefulWidget`). This was needed because `videosRepositoryProvider` is a `FutureProvider<VideosRepository>` (async; depends on `SharedPreferences.getInstance()`) while `photosRepositoryProvider` is a sync `Provider` — a direct provider swap didn't work. Unified `PhotosRepository.addReaction` return type from `Future<void>` → `Future<({String id, String type})>` to match `VideosRepository.addReaction`. This also **fixed a pre-existing bug**: the widget previously discarded the API response on add, so `_userReactionIds[type]` stayed empty; a subsequent unlike in the same session hit the `reactionId.isNotEmpty` guard, never fired DELETE, and the reaction re-appeared on the next 30s poll. The refactor captures the id (with `mounted` guard) so same-session add+remove works end-to-end. Callsite updates: `photo_card_widget.dart:128-140` (converted `StatelessWidget` → `ConsumerWidget`), `photo_detail_screen.dart:163-173` (already `ConsumerWidget`), `video_card_widget.dart:82-100` (converted `StatelessWidget` → `ConsumerWidget`, reaction row gated on `video.isReady` because backend rejects reactions on non-active media — processing/failed/local-pending cards intentionally unchanged). `flutter analyze` green — zero new issues. Video player screen reactions explicitly out of scope (parity with photo detail is a separate follow-up). |
| Uploader-only delete on feed cards + dialog consolidation | Done | Users needed a one-tap recovery path for accidental uploads. Prior state: `photo_detail_screen.dart:45-119` had Delete but was visible to all viewers and didn't invalidate the feed (photo lingered 30s); `video_player_screen.dart:357-405` had Delete + feed invalidation but also visible to all; neither feed card had any delete affordance. Backend (`photos.ts:424-466`, `videos.ts:725-763`) already enforces uploader-only (403 for others) with CASCADE on reactions and Decision Q5 discard-on-callback for delete-during-transcode — zero server changes needed. **New:** `app/lib/widgets/confirm_destructive_dialog.dart` — shared `confirmDestructive(context, title, body, confirmLabel)` helper lifting the canonical dark-theme `AlertDialog` styling (`0xFF1A2035` bg, `0xFFEF4444` destructive button, 16px radius, 70% alpha content) out of 5 duplicated sites. `app/lib/widgets/media_owner_menu.dart` — shared `MediaOwnerMenu` widget renders a 3-dot `PopupMenuButton` in the card header when `isOwner && !isSelecting`; handles confirm + SnackBar + `_deleteErrorMessage` mapping (`FORBIDDEN` / `PHOTO_NOT_FOUND` / `VIDEO_NOT_FOUND` / timeout → friendly strings, 404 treated as "already removed" since feed was invalidated pre-throw). **Applied to:** `photo_card_widget.dart` + `video_card_widget.dart` (new 3-dot via `MediaOwnerMenu`); `photo_detail_screen.dart` (delete item now gated on `isOwner`, invalidates `eventPhotosProvider(photo.eventId)` before pop); `video_player_screen.dart` (delete item gated via `videoDetailProvider` watch, watches `authStateProvider`). **Video-specific:** delete flow in card + player retires any `LocalPendingVideo` whose `serverVideoId` matches the deleted server video — fixes a ghost-card regression (would otherwise re-render "Polishing your video" after server delete because the feed merge would see only the local pending item). **Existing-dialog consolidation:** the 5 pre-existing `AlertDialog`-based destructive confirmations (`event_detail_screen._showDeleteEventDialog`, `clique_detail_screen._showRemoveMemberDialog` / `_showLeaveCliqueDialog` / `_showDeleteCliqueDialog`, `profile_screen` delete-account) now all call `confirmDestructive` — single source of truth for destructive-confirm styling. Username `Text` in both card widgets gained `overflow: TextOverflow.ellipsis` so long display names don't push the 3-dot off-screen. `flutter analyze` green — 61 issues, same pre-existing baseline, zero new. Out of scope: mid-upload cancel for local pending videos (deferred to v1.5); multi-select delete on feed. |
| 13+ age gate at sign-up — claim-based, backend-enforced | Done (2026-04-18) | **Pivoted from the Entra Custom Authentication Extension approach** after multi-day debugging revealed it's not a supported pattern in External ID (Microsoft's own migration docs: *"Age gating isn't currently supported in Microsoft Entra External ID"*). Instead: Entra's `SignUpSignIn` user flow still collects `dateOfBirth` as a custom attribute once; the attribute is emitted on every access token via the documented Directory schema extension claim path; backend `authVerify` (`backend/src/functions/auth.ts`) reads the claim on first login, computes age via existing `ageUtils.calculateAge`, and branches: ≥13 → upsert user with `age_verified_at = NOW()` + `age_gate_passed` telemetry; <13 → HTTP 403 `AGE_VERIFICATION_FAILED` + best-effort Microsoft Graph `DELETE /users/{oid}` via `entraGraphClient.ts` + `age_gate_denied_under_13` telemetry. Grandfathered users (no DOB claim) pass silently with `age_verified_at` null. **New code:** `auth.ts` additions (`decideAgeGate`, `extractDobFromClaims`, `parseAnyDob`), `entraGraphClient.ts`, migration `008_user_age_verification.sql` adding `users.age_verified_at`. **Removed code:** `validateAge.ts` (CAE function — deleted), `entraCaeTokenVerifier.ts` + tests (were needed when EasyAuth proved opaque; no longer used). **Portal state:** EasyAuth removed from `func-cliquepix-fresh`; CAE detached from the `SignUpSignIn` user flow; `dateOfBirth` added as a token claim on the CLIQUE Pix app via Enterprise App → SSO → Attributes & Claims (Directory schema extension from b2c-extensions-app); Function App managed identity granted `User.ReadWrite.All` on Microsoft Graph for the under-13 cleanup. **Tests:** 16 new unit tests covering the age-gate decision logic + 20 existing ageUtils tests, all green. **Client UX (commit `1a37af1`):** `AuthNotifier.signIn` in `auth_providers.dart` detects the structured 403 `AGE_VERIFICATION_FAILED` response, resets the MSAL session to avoid retry loops, and passes the backend's message through to `AuthError` — the login screen shows the red banner *"You must be at least 13 years old to use CLIQUE Pix."* instead of the previous generic "Sign in failed. Please try again." See `docs/AGE_VERIFICATION_RUNBOOK.md` for the full architecture + troubleshooting. |

| Task | Status | Notes |
|------|--------|-------|
| APIM: X-Azure-FDID header validation | Not done | Restrict APIM to Front Door traffic only |
| Google OAuth: add second redirect URI | Not done | May need tenant-ID-format URI |
| Release signing key | Not done | Needed for production APK and Play Store; assetlinks.json must be updated with release SHA256 |
| App Store / Play Store submission | Not done | |
| iOS Associated Domains entitlement | Not done | Requires Xcode on Mac: Signing & Capabilities → `applinks:clique-pix.com` |
| Push notification end-to-end verification | In progress | Full pipeline implemented (backend FCM send confirmed via App Insights, client foreground/background/terminated handlers, channel creation, Android 13+ permission). Needs on-device verification. |

### End-to-End Validation

| Step | Status |
|------|--------|
| 1. Sign up / sign in | Done (2026-03-26) |
| 2. Create a Clique | Done (2026-03-26) |
| 3. Generate invite link/QR | Done (2026-03-31) — QR code encodes `https://clique-pix.com/invite/{code}` |
| 4. Join Clique via invite (QR scan) | Done (2026-03-31) — invite landing page loads (no more 404), join succeeds, joiner appears in clique |
| 5. Create Event (24h/3d/7d) | Done (2026-03-26) |
| 6. Capture photo in-app | Done (2026-03-26) — photo confirmed in database |
| 7. Upload photo (compress → SAS → blob → confirm) | In progress — double-pop bug fixed (user never saw Upload button); Dio config fixed; needs retest |
| 8. See photo in feed | In progress — type cast bug fixed, needs retest after upload pipeline fix |
| 9. React to photo | Not tested |
| 10. Save photo to device | Not tested |
| 11. Share photo externally | Not tested |
| 12. Receive push notification (clique join) | In progress — backend sends FCM successfully (confirmed via App Insights telemetry), client has foreground/background/terminated handlers + notification channel + Android 13+ permission. Needs on-device verification. |
| 13. Auto-deletion after expiry | Not tested |
| 14. Graceful re-login (Layer 5) | Not tested |
| 15. Owner sees new member (auto-refresh) | Partial — pull-to-refresh works, 30s polling implemented, but auto-refresh not confirmed working on device |
| 16. Owner removes member from clique | Done (2026-04-01) — owner taps member → confirm dialog → member removed → list refreshes |
| 17. Member leaves clique | Done (2026-04-01) — member taps "Leave Clique" → confirm → navigates to cliques list |
| 18. Removed member graceful redirect | Done (2026-04-01) — 404 detection auto-navigates removed user back to cliques list with SnackBar |
| 19. Event organizer deletes event | Not tested — delete icon visible to creator, confirmation dialog, blob cleanup + cascade delete |
| 20. Non-organizer cannot delete event | Not tested — delete icon should not appear for non-creators |
| 21. Multi-select media download | Not tested — enter selection mode, select photos + videos, download with progress bar, dynamic label |
| 22. Photo card uploader name readable | Not tested — white text on dark card background |
| 23. Event creator name displayed | Not tested — "Created by {name}" visible on event detail screen |
| 24. Clear all notifications | Not tested — tap trash sweep icon in AppBar → confirm → all notifications cleared |
| 25. Swipe to dismiss notification | Not tested — swipe left on individual notification → red background → deleted |
| 26. Copy user ID from profile | Not tested — tap copy icon next to UUID → clipboard |
| 27. Delete account | Not tested — tap Delete Account → confirm → account removed → redirected to login |
