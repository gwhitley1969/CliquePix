# Age Verification Runbook — Claim-Based Backend Enforcement

**Requirement:** Clique Pix users must be 13+ at sign-up.

**Strategy:** Entra External ID's `SignUpSignIn` user flow collects `dateOfBirth` as a required custom attribute during first-time sign-up. The attribute is emitted on every access token as a directory-schema-extension claim. Clique Pix's backend (`POST /api/auth/verify`) reads that claim on first login, computes age server-side, blocks under-13 users with HTTP 403, and best-effort deletes their orphaned Entra account via Microsoft Graph.

**Why not Custom Authentication Extensions?** Microsoft's own migration docs state: *"Age gating isn't currently supported in Microsoft Entra External ID."* The CAE `OnAttributeCollectionSubmit` pattern is a community workaround, not a supported path — it proved brittle for us (weeks of generic "Something went wrong" errors, opaque EasyAuth rejections, tokens with `iss` values that disagreed with Microsoft's own documented format). Claim-based validation uses officially-supported Entra features and runs inside code we own, so failures are debuggable.

**Paired code:** `backend/src/functions/auth.ts` (`authVerify` handler + `decideAgeGate` pure function), `backend/src/shared/utils/ageUtils.ts`, `backend/src/shared/auth/entraGraphClient.ts`.

---

## Architecture

```
┌───────────────────┐    ┌─────────────────────┐    ┌────────────────────────┐
│  Flutter signup   │───▶│  Entra user flow    │───▶│  Entra issues access   │
│  (MSAL redirect)  │    │  SignUpSignIn       │    │  token with            │
│                   │    │  collects DOB once  │    │  extension_<guid>_     │
│                   │    │                     │    │  dateOfBirth claim     │
└───────────────────┘    └─────────────────────┘    └───────────┬────────────┘
                                                                │
                                     ┌──────────────────────────▼──────────────┐
                                     │  Flutter calls                          │
                                     │  POST /api/auth/verify + Bearer token   │
                                     └──────────────────────────┬──────────────┘
                                                                │
  ┌─────────────────────────────────────────────────────────────▼─────────────────────────┐
  │  backend/auth.ts  authVerify                                                           │
  │    1. Validate JWT (signature, iss, aud) via jwks-rsa                                  │
  │    2. decideAgeGate(payload) → {pass, block, grandfather}                              │
  │         if block → return 403 AGE_VERIFICATION_FAILED                                  │
  │                    + best-effort deleteEntraUserByOid(oid) via Graph (fire-and-forget) │
  │                    + trackEvent 'age_gate_denied_under_13'                             │
  │         if pass → upsert user row with age_verified_at=NOW() + trackEvent 'age_gate_passed' │
  │         if grandfather → upsert user row, age_verified_at stays null                   │
  └────────────────────────────────────────────────────────────────────────────────────────┘
```

**Grandfather path** exists for users created before the age gate was deployed — their tokens have no DOB claim, so we let them through. New users always have the claim (user flow requires DOB), so grandfather is effectively unreachable for post-deployment signups.

## Prerequisites

- Owner/Application Administrator on the CIAM tenant `cliquepix.onmicrosoft.com` (tenant ID `27748e01-d49f-4f0b-b78f-b97c16be69dc`).
- Access to both `entra.microsoft.com` and `portal.azure.com`.
- Function App `func-cliquepix-fresh` has a system-assigned managed identity (pre-existing).
- Backend migration `008_user_age_verification.sql` applied (adds `users.age_verified_at`).

---

## Step 1 — Create the `dateOfBirth` custom attribute

If this already exists from the previous CAE approach, skip to step 2.

**Path:** `entra.microsoft.com` → **Entra ID** → **External Identities** → **Overview** → **Custom user attributes** → **+ Add**

- **Name:** `dateOfBirth`
- **Data type:** **String** (Entra's date input widget renders for string type; value submits as `YYYY-MM-DD`)
- **Description:** `User's date of birth — collected at sign-up for 13+ age verification`

Click **Create**.

> Programmatic name becomes `extension_{b2c-extensions-app-appId-without-hyphens}_dateOfBirth`. Our backend matches by case-insensitive substring "dateofbirth" so you never need to paste the GUID.

## Step 2 — Add `dateOfBirth` to the SignUpSignIn user flow

**Path:** `entra.microsoft.com` → **Entra ID** → **External Identities** → **User flows** → **`SignUpSignIn`**

### 2a. Collect the attribute
- Left menu → **User attributes** → tick **dateOfBirth** → **Save**.

### 2b. Give the field a clear label
- Left menu → **Page layouts** → **Local account sign up** → find the `dateOfBirth` row → set **Label** to `Date of Birth (must be 13+)` → **Save**.

### 2c. If a Custom Authentication Extension was previously attached — detach it
- Left menu → **Custom authentication extensions**.
- Row **"When a user submits their information"**: click the edit pencil → choose **None** → **Select** → **Save**.
- The claim-based approach doesn't need any extension; this must be detached or signups will fail calling the (now-deleted) `validate-age` endpoint.

## Step 3 — Emit `dateOfBirth` as a token claim on the Clique Pix app

**Path:** `entra.microsoft.com` → **Entra ID** → **App registrations** → **Clique Pix** (client ID `7db01206-135b-4a34-a4d5-2622d1a888bf`)

1. **Overview** → click **Managed application in local directory** (link in Essentials). Lands on the Enterprise Application.
2. Left menu → **Single sign-on**.
3. **Attributes & Claims** → **Edit** (pencil).
4. (If a prior `ageVerified` claim exists from the CAE era, delete it.)
5. **+ Add new claim**
   - **Name:** `dateOfBirth`
   - **Source:** **Directory schema extension**
   - Click **Select** → choose **b2c-extensions-app** → tick `dateOfBirth` → **Add**
6. **Save**

### 3a. Verify the app manifest

Still on `entra.microsoft.com` → **Entra ID** → **App registrations** → **Clique Pix** → **Manifest**. Confirm both flags are set (the Microsoft Graph manifest format):

- `acceptMappedClaims: true`
- `accessTokenAcceptedVersion: 2`

Without these, Entra won't include the extension claim in the JWT.

## Step 4 — Function App managed identity → Microsoft Graph `User.ReadWrite.All`

Required for the best-effort under-13 Entra account deletion. Easiest via CLI:

```bash
FUNC_MI=$(az functionapp identity show --name func-cliquepix-fresh --resource-group rg-cliquepix-prod --query principalId -o tsv)
GRAPH_SP=$(az ad sp show --id 00000003-0000-0000-c000-000000000000 --query id -o tsv)
ROLE_ID=$(az ad sp show --id 00000003-0000-0000-c000-000000000000 --query "appRoles[?value=='User.ReadWrite.All' && allowedMemberTypes[0]=='Application'].id" -o tsv)

az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$FUNC_MI/appRoleAssignments" \
  --body "{\"principalId\":\"$FUNC_MI\",\"resourceId\":\"$GRAPH_SP\",\"appRoleId\":\"$ROLE_ID\"}"
```

If the delete call fails at runtime, the user still can't use Clique Pix (403 stays 403) — they just leave an orphan Entra account. Telemetry event `age_gate_entra_delete_failed` flags these for manual cleanup.

---

## End-to-end verification

### 5a. Over-13 happy path

1. Fresh private browser / clear MSAL cache / fresh email
2. Trigger Clique Pix signup
3. Entra-hosted form asks for Date of Birth (and any other configured attributes)
4. Enter `1990-05-15` → submit
5. Expect: signup completes, app lands on home screen
6. App Insights (`appi-cliquepix-prod`):
   ```kql
   customEvents
   | where name in ('age_gate_passed', 'auth_verify_success')
   | where timestamp > ago(10m)
   ```
   Both rows should appear. `age_gate_passed` has `ageBucket: 25-34` in customDimensions.
7. PostgreSQL:
   ```sql
   SELECT email_or_phone, age_verified_at FROM users WHERE email_or_phone = '<test-email>';
   ```
   `age_verified_at` should be a timestamp ~30 seconds old.

### 5b. Under-13 block path

1. Fresh private browser + fresh email
2. Trigger signup → enter DOB `2020-01-01` → submit
3. Expect: signup completes *in Entra* (new account created), but the app returns to the login screen with a red error banner reading *"You must be at least 13 years old to use Clique Pix."* (surfaced from backend `AGE_VERIFICATION_FAILED` response via `app/lib/features/auth/presentation/auth_providers.dart:AuthNotifier.signIn`; `resetSession()` is called to clear the MSAL cache so retries start clean)
4. App Insights:
   ```kql
   customEvents
   | where name == 'age_gate_denied_under_13'
   | where timestamp > ago(5m)
   ```
5. Wait ~30 seconds, then verify Entra account deletion:
   ```bash
   az rest --method GET --uri "https://graph.microsoft.com/v1.0/users?\$filter=mail eq '<test-email>'"
   ```
   Should return empty (`value: []`). If the user still exists, check `age_gate_entra_delete_failed` telemetry — managed-identity token may have propagation delay on first call.

### 5c. Returning-user fast path

1. Sign out of the over-13 test account
2. Sign back in with the same email
3. Expect: sign-in form only (no DOB re-prompt), app lands home
4. PostgreSQL: `age_verified_at` unchanged (the upsert uses `COALESCE` to preserve the original timestamp)

---

## Troubleshooting

### "Something went wrong" on the Entra-hosted signup page
- **Cause:** CAE is still attached to the user flow from the old architecture and is calling a 404 endpoint (`/api/validate-age` was deleted).
- **Fix:** Step 2c above — detach the CAE. Retest.

### Signup completes but `age_verified_at` stays null after Step 5a
- **Cause:** `dateOfBirth` claim is not in the JWT. Confirm Step 3 (Attributes & Claims) saved correctly. Decode a fresh access token at `https://jwt.ms` and look for `extension_<guid>_dateOfBirth` in the claim set.
- Also confirm Step 3a — without `acceptMappedClaims: true` + `accessTokenAcceptedVersion: 2`, Entra silently omits extension claims.

### Under-13 signup lets the user in
- **Cause:** `dateOfBirth` claim missing from JWT → `decideAgeGate` returns `grandfather`, and grandfathered users pass. Same fix as above (verify the claim is present).
- **Secondary cause:** DOB format Entra emits isn't one of YYYY-MM-DD / MM/DD/YYYY / MMDDYYYY. Check `customEvents` with `name == "auth_verify_success"` — if DOB claim exists but is in an unexpected format, `parseAnyDob` returns null → grandfather path. Add the format to `parseAnyDob` in `backend/src/functions/auth.ts`.

### `age_gate_entra_delete_failed` events piling up
- **Cause:** Function App managed identity lacks `User.ReadWrite.All` on Graph (Step 4 not done) or Graph admin consent never granted.
- **Verify:** `az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/<func-mi-oid>/appRoleAssignments"` should list the assignment.

---

## Rollback

This architecture has no runtime dependencies on the CAE infrastructure. To roll back:

1. Drop the `age_verified_at` column: `ALTER TABLE users DROP COLUMN age_verified_at;`
2. Remove the `dateOfBirth` claim from the Clique Pix Enterprise App's Attributes & Claims
3. Revert the code commit that added `decideAgeGate` + `deleteEntraUserByOid`

The Entra-side DOB attribute + user flow remain — they're harmless without the backend check.

---

## Policy alignment

- `website/privacy.html` §2.2 + §11 — DOB stored in Entra (Microsoft's identity store), not Clique Pix's product database. Accurate under this architecture.
- `website/terms.html` §2 — 13+ requirement. Unchanged.
- `MIN_AGE = 13` constant lives in `backend/src/shared/utils/ageUtils.ts`. Mirror in `app/lib/core/utils/age_utils.dart` if the policy ever changes.

## Cost

- One extra SELECT/UPDATE on `users` per login (already happening in `authVerify`) — no cost delta.
- One Microsoft Graph DELETE per under-13 signup — effectively free within Graph's free quota.

---

## Deprecated — Custom Authentication Extension approach (kept for reference)

<details>
<summary>Expand — the CAE-based approach that we tried and abandoned</summary>

The earlier iteration used a Custom Authentication Extension on the `OnAttributeCollectionSubmit` event, calling an Azure Function `validate-age` that returned `modifyAttributeValues {ageVerified: true}` or `showBlockPage`. That approach is documented in git history (see commits before `feat(auth): claim-based post-auth age gate replaces Custom Authentication Extension`) and in MAB's `AGE_VERIFICATION_IMPLEMENTATION.md`.

Key failure modes we hit — useful to remember if this is ever reconsidered:

1. **EasyAuth silently rejected every CAE call** with no App Insights visibility, producing a generic "Something went wrong" page. Microsoft's own docs acknowledge this: the error "is intentionally generic. To troubleshoot, check the sign-in logs for the error codes."
2. **CAE token `iss` format disagreed with docs** — Microsoft's docs say the issuer uses the `{tenantDomain}.ciamlogin.com` subdomain, but the actual token's `iss` used the `{tenantId}.ciamlogin.com` form. Detected only by in-code JWT validation logging.
3. **Microsoft's own migration guide states age gating is unsupported in External ID.** The CAE-on-OnAttributeCollectionSubmit pattern is community-built.

The code that implemented this lived at `backend/src/functions/validateAge.ts` + `backend/src/shared/auth/entraCaeTokenVerifier.ts`. Both deleted in the pivot commit.

</details>
