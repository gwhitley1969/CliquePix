// ─────────────────────────────────────────────────────────────────────────────
// TOMBSTONE — APIM was removed from the CLIQUE Pix architecture on 2026-07-05.
// ─────────────────────────────────────────────────────────────────────────────
//
// This file previously declared the full `apim-cliquepix-003` (Basic v2) API
// Management service. The service was removed as part of the July 2026 FinOps
// pass: its only remaining live function was CORS injection for two origins
// (~$148/month for a CORS header). Rate limiting had already been removed at
// every scope after the six 429 incidents of 2026-04/05, and JWT auth has
// always lived in the Functions code (`authLevel: 'anonymous'` + authMiddleware).
//
// The API chain is now:  client → Azure Front Door (api.clique-pix.com,
// route default-route → origin group func-origin-group) → func-cliquepix-fresh.
//
//   • CORS source of truth: Function App platform CORS
//     (`az functionapp cors show -g rg-cliquepix-prod -n func-cliquepix-fresh`)
//     — allowed origins: https://clique-pix.com, http://localhost:5173
//   • Transcoder callback: FUNCTION_CALLBACK_URL now points at
//     https://api.clique-pix.com/api/internal/video-processing-complete
//   • Function App is (post-soak) locked to Front Door traffic via an access
//     restriction on service tag AzureFrontDoor.Backend with
//     X-Azure-FDID = 4e41fded-8d53-4ecd-bc17-af06024ecfad
//
// Full declaration history: `git log -- bicep/apim/main.bicep`.
// The 6-incident APIM rate-limit history lives in git history of
// apim_policy.xml and in docs/BETA_OPERATIONS_RUNBOOK.md §2 (historical).
// Migration record: docs/DEPLOYMENT_STATUS.md, 2026-07-05 entry.
//
// If an API gateway is ever re-introduced, do NOT re-add <rate-limit>,
// <rate-limit-by-key>, or <quota> at any scope without load-testing limits
// against actual traffic patterns first — see the incident history.
// ─────────────────────────────────────────────────────────────────────────────
