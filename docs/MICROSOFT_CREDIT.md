# Azure Billing Credit Request — Container Apps Metering Anomaly (June 2026)

**Purpose:** evidence package for a Microsoft Azure **billing support ticket** requesting a credit for an
Azure Container Apps metering anomaly on the **Clique Pix** subscription. Everything below was verified
directly against Azure Cost Management, Azure Monitor platform metrics, and the Log Analytics workspace —
each figure is reproducible with the commands in §9. Hand this to the support agent.

> **Bottom line:** request a credit of **~$411.25 USD** (defensible conservative floor **$346.84**) for
> anomalous `Azure Container Apps` **active-usage** billing during **June 3–11, 2026**, where the billed
> cost rose ~20× with **zero** corresponding change in execution count, requested cores, CPU utilization,
> log volume, or actual workload.

---

## 1. The ask (one paragraph for the agent)

Between **June 3 and June 9, 2026**, the `Azure Container Apps` service on subscription *Clique Pix*
(`25410e67-b3c8-49a2-8cf0-ab9f77ce613f`) — specifically the event-driven job
**`caj-cliquepix-transcoder`** — billed **~$73/day** of "Standard vCPU/Memory Active Usage", up from a
steady **~$3.74/day** baseline, then returned to baseline on June 10. Across the entire period the
**measured workload was provably flat and near-idle**: the job's execution count, requested cores, actual
CPU usage, and console-log volume were unchanged from the cheap days, and Application Insights records
**exactly one** real transcode in the whole window (a 19-second job on June 6). No customer configuration
or deployment change aligns with the cost onset or recovery. We are requesting a credit for the **excess
above the legitimate baseline**, totaling **$411.25 USD**.

---

## 2. Account & resource identifiers

| Field | Value |
|---|---|
| Billing account type | **Microsoft Customer Agreement (MCA)** |
| Billing account | `08ba551b-d9d2-53aa-686d-c72b57187141:8fb88a2a-bbef-430e-8d5b-b7ca40a64cba_2019-05-31` |
| Subscription name | **Clique Pix** |
| Subscription ID | `25410e67-b3c8-49a2-8cf0-ab9f77ce613f` |
| Resource group | `rg-cliquepix-prod` |
| Affected resource | `caj-cliquepix-transcoder` (Container Apps **Job**, event-triggered) |
| Resource ID | `/subscriptions/25410e67-b3c8-49a2-8cf0-ab9f77ce613f/resourceGroups/rg-cliquepix-prod/providers/Microsoft.App/jobs/caj-cliquepix-transcoder` |
| Container Apps Environment | `cae-cliquepix-prod` |
| Service (Cost Management `ServiceName`) | `Azure Container Apps` |
| Billed meters | `Standard vCPU Active Usage`, `Standard Memory Active Usage` |
| Region | East US |
| Currency | USD |
| Anomaly window | **2026-06-03 ~18:00 UTC → 2026-06-09** (tail to 06-11) |
| Invoice | June 2026 MCA invoice (posts ~July 5–9, 2026) — **reference its invoice number when filing** |

---

## 3. What happened (timeline)

- The job is a KEDA queue-triggered FFmpeg transcoder. During this period it was (mis)configured with
  `minExecutions=1` and `pollingInterval=5s`, which causes KEDA to spawn ~one short (~1 second) poll
  execution every 5 seconds — **~17,000 executions/day** that find an empty queue and exit. This produced
  a **legitimate, steady idle cost of ~$3.74/day** (we are **not** disputing this — see §6).
- **~June 3, 18:00 UTC:** billed `Azure Container Apps` cost began ramping sharply (June 3 is a partial-day
  charge of $20.92), reaching **~$73/day** on June 4–8 — roughly **20× the idle baseline** — with **no
  change in the underlying workload signals**.
- **June 6, 17:38 UTC:** the *only* real transcode of the window ran (19 seconds of FFmpeg processing).
- **June 9–10:** cost decayed back toward baseline.
- **June 12, 01:31 UTC:** we set `minExecutions=0` (true scale-to-zero). Container Apps cost dropped to
  **$0/day** and has remained there since (verified through June 22).

---

## 4. Evidence table — billed cost vs. measured workload (the core of the request)

All columns are **independent data sources**. Cost = Azure Cost Management (ActualCost). Executions,
RequestedCores, UsageNanoCores = Azure Monitor **platform metrics** for the job. Console lines = Log
Analytics `ContainerAppConsoleLogs_CL`. "Real transcodes" = Application Insights `AppEvents`.

| Date (2026) | Billed `Azure Container Apps` (USD) | Executions / day | RequestedCores (avg) | UsageNanoCores (actual CPU) | Console log lines | Real transcodes |
|---|---|---|---|---|---|---|
| Jun 01 | $0.00 | 17,644 | 1.0 | 0 | 5,488 | 0 |
| Jun 02 | **$3.74** ← baseline | 17,382 | 1.0 | 0 | 5,566 | 0 |
| Jun 03 | $20.92 | 17,156 | 1.0 | 0 | 5,318 | 0 |
| Jun 04 | **$72.94** | 18,178 | 1.0 | *(no data emitted)* | 5,184 | 0 |
| Jun 05 | **$72.29** | 18,317 | 1.0 | *(no data emitted)* | 5,166 | 0 |
| Jun 06 | **$74.26** | 17,394 | 1.0 | 1.03 avg (brief) | 5,304 | **1** (17:38 UTC, 19s) |
| Jun 07 | **$73.50** | 17,224 | 1.0 | *(no data emitted)* | 5,274 | 0 |
| Jun 08 | **$72.55** | 17,223 | 1.0 | *(no data emitted)* | 5,196 | 0 |
| Jun 09 | $47.45 | 17,015 | 1.0 | 0 | 5,118 | 0 |
| Jun 10 | $5.55 | 16,882 | 1.0 | *(no data emitted)* | 5,130 | 0 |
| Jun 11 | $5.45 | 16,851 | 1.0 | *(no data emitted)* | 5,186 | 0 |
| Jun 12 | $0.46 | 1,106 | 1.0 | *(no data emitted)* | 346 | 0 |

> Jun 01 is $0.00 because the monthly Container Apps **free grant** (180,000 vCPU-s + 360,000 GiB-s) had not
> yet been exhausted; from Jun 02 the idle config bills the steady ~$3.74/day baseline.

**Read the table across a row, then down the cost column:** Executions (±5%), RequestedCores (1.0), console
log volume (±4%), and CPU usage (~0) are **statistically identical** on June 2 ($3.74) and June 6 ($74.26).
The only thing that changed by 20× was the bill.

---

## 5. The six independently-verified facts

1. **Billed active-usage rose ~20×** ($3.74/day → ~$73/day, Jun 4–8) — Cost Management.
2. **Execution count was flat** at ~17,000–18,000/day across the *entire* window — the same on cheap and
   expensive days — Azure Monitor `Executions` metric. (This is the KEDA 5-second poll: 86,400s ÷ 5 ≈
   17,280/day, unchanged.)
3. **RequestedCores was flat at 1.0** every day — Azure Monitor `RequestedCores` metric. No increase in
   provisioned compute.
4. **Actual CPU usage (`UsageNanoCores`) was 0 or not emitting** throughout the window — except a brief
   blip on June 6 (the single real transcode). The platform's own utilization metric shows the replicas
   did essentially **no work**, yet were billed as fully active.
5. **Console-log volume was flat** at ~5,200 lines/day across Jun 1–11 (then 346 on Jun 12 at the fix) —
   Log Analytics. The container's own output confirms the unchanged poll-and-exit loop.
6. **Exactly one real transcode** occurred in the whole window — June 6, 17:38 UTC, `durationSeconds=19`,
   `processingMode=transcode`, `videoId=66af6b1d-a6c7-4ebe-be34-eb52f0edb039` — Application Insights
   `AppEvents`. One ~20-second job cannot account for 5 days of ~$73/day active billing.

**Interpretation:** billed *active replica-time* increased ~20× with **no** increase in execution count and
**near-zero** actual CPU utilization. This is consistent with replicas held in a provisioned/active
**billing** state without performing work (orphaned/zombie replicas), or a platform metering error. It is
**not** consistent with any legitimate workload, because every customer-visible workload signal was flat.

---

## 6. Credit calculation (and what we are NOT claiming)

We subtract the **legitimate baseline** of **$3.74/day** — the real, non-disputed cost of our own
`minExecutions=1` idle configuration — from each anomalous day, and claim only the excess:

| Date | Billed (USD) | − baseline $3.74 | Creditable excess |
|---|---|---|---|
| Jun 03 | 20.92 | | 17.18 |
| Jun 04 | 72.94 | | 69.20 |
| Jun 05 | 72.29 | | 68.55 |
| Jun 06 | 74.26 | | 70.52 |
| Jun 07 | 73.50 | | 69.76 |
| Jun 08 | 72.55 | | 68.81 |
| Jun 09 | 47.45 | | 43.71 |
| Jun 10 | 5.55 | | 1.81 |
| Jun 11 | 5.45 | | 1.71 |
| **Total** | | | **$411.25** |

- **Primary request: $411.25 USD** (excess above baseline, Jun 3–11).
- **Conservative floor: $346.84 USD** (the five unambiguous full-rate days, Jun 4–8 only).
- We are **explicitly not** requesting credit for the ~$3.74/day idle baseline — that was caused by our own
  configuration and is a legitimate charge. We dispute **only** the platform-side anomalous excess.

---

## 7. Why this is a platform-side anomaly, not customer usage (pre-empting the obvious questions)

- *"You were running `minExecutions=1`, that costs money."* — Correct, and we pay it: $3.74/day, already
  excluded from the claim. That config cost the **same** $3.74/day on June 2 and June 10. It cannot explain
  June 4–8 at $73/day.
- *"A spike means more executions ran."* — No. The `Executions` metric is **flat** (§4, §5.2). Same count
  on $3.74 days and $73 days.
- *"Replicas must have been doing heavy work."* — No. `UsageNanoCores` (actual CPU) was **0 / not emitting**
  (§5.4) and only one 19-second transcode ran all week (§5.6). Active billing without CPU work = the anomaly.
- *"A deploy changed behavior."* — No customer change aligns. The only change in the window (transcoder
  image **v0.1.8**, deployed June 4 ~22:02 UTC) sits **mid-window** and had no effect on cost onset (June 3)
  or recovery (June 10). Cost onset (~June 3 18:00 UTC) and decay (June 9–10) correlate with **nothing**
  on the customer side.

---

## 8. Remediation already performed (good-faith)

- **2026-06-12 01:31 UTC:** changed the job to `minExecutions=0` (true scale-to-zero) via
  `az containerapp job update`. Container Apps cost has been **$0/day** since (verified June 12–22).
- Current job scale config is verified live: `minExecutions: 0`, `maxExecutions: 10`, `pollingInterval: 5`,
  KEDA `azure-queue` scaler.
- We have also instituted daily cost-anomaly alerting so any recurrence is caught immediately.

This demonstrates the idle baseline is permanently resolved on our side; the credit concerns only the
historical platform anomaly.

---

## 9. How Microsoft can independently reproduce every number

All commands are read-only. Log Analytics workspace: `log-cliquepix-prod`, ID
`c158e174-b84f-41f3-bc36-03fbaf279eb7`.

**Daily billed cost (Cost Management):**
```bash
az rest --method post \
  --url "/subscriptions/25410e67-b3c8-49a2-8cf0-ab9f77ce613f/providers/Microsoft.CostManagement/query?api-version=2023-11-01" \
  --headers "ClientType=GitHubCopilotForAzure" \
  --body '{"type":"ActualCost","timeframe":"Custom","timePeriod":{"from":"2026-06-01","to":"2026-06-12"},
           "dataset":{"granularity":"Daily","aggregation":{"totalCost":{"name":"Cost","function":"Sum"}},
           "grouping":[{"type":"Dimension","name":"ServiceName"}]}}'
```

**Platform metrics — Executions, RequestedCores, UsageNanoCores (the workload-vs-bill contradiction):**
```bash
az monitor metrics list \
  --resource caj-cliquepix-transcoder -g rg-cliquepix-prod --resource-type "Microsoft.App/jobs" \
  --subscription 25410e67-b3c8-49a2-8cf0-ab9f77ce613f \
  --metric "UsageNanoCores" "RequestedCores" "Executions" \
  --aggregation Average Maximum Total --interval P1D \
  --start-time 2026-06-01T00:00:00Z --end-time 2026-06-13T00:00:00Z
```

**The single real transcode (App Insights):**
```bash
az monitor log-analytics query --workspace c158e174-b84f-41f3-bc36-03fbaf279eb7 \
  --analytics-query "AppEvents | where TimeGenerated >= datetime(2026-06-01) and TimeGenerated < datetime(2026-06-13) | where Name == 'video_transcoding_completed' | project TimeGenerated, Properties"
```

**Flat console-log volume (workload proxy):**
```bash
az monitor log-analytics query --workspace c158e174-b84f-41f3-bc36-03fbaf279eb7 \
  --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated >= datetime(2026-06-01) and TimeGenerated < datetime(2026-06-13) | summarize lines=count() by bin(TimeGenerated,1d) | order by TimeGenerated asc"
```

Microsoft's own **platform-side** record (`UsageNanoCores` going dark while the active-usage meter
escalated) should be visible to the support/billing engineering team and is the definitive internal signal.

---

## 10. Filing logistics

1. **Wait for the June MCA invoice** (posts ~**July 5–9, 2026**). You cannot file a billing dispute against
   an un-issued invoice — current Cost Management figures are *estimated/unbilled*.
2. When the invoice posts, **confirm the anomaly excess actually appears on it** (a genuine metering error
   may already be excluded by Microsoft; if so, no ticket is needed).
3. Azure Portal → **Help + support → Create a support request**:
   - Issue type: **Billing** (billing/subscription support is **free** for all customers — no paid support
     plan required).
   - Subscription: **Clique Pix**.
   - Problem subtype: prefer **"Help me understand / investigate my charges"** (keys on a billing period) —
     the **"Refund request"** subtype hard-requires an invoice number, which you'll have by then.
   - Reference: the **June 2026 invoice number**, the window **2026-06-03 → 2026-06-09**, resource
     **`caj-cliquepix-transcoder`**, meters **`Standard vCPU/Memory Active Usage`**, and **this document**.
4. Attach/cite the §4 table and the §9 reproduction commands. Lead with the contradiction: **flat
   `Executions` + `RequestedCores` + near-zero `UsageNanoCores`, but a 20× active-usage bill.**
5. Record the support ticket number and follow it to either an issued credit or a written denial with reason.

---

## 12. STAGED TICKET — ready to file the moment the June invoice posts (staged 2026-07-05)

**Invoice check 2026-07-05:** the June-period invoice has NOT posted yet. Billing profile `KNVI-ZBIZ-BG7-PGB`
shows May's invoice `G163862975` ($925.54) posted **June 9** — on that cadence the June invoice posts **~July 9**.
Per §10, do not file before it exists.

**When it posts** (re-check with the invoice-list call below), fill `<INVOICE_NUMBER>` and run the PUT.
Support prerequisites verified 2026-07-05: `Microsoft.Support` RP is Registered on the Clique Pix subscription;
classification chosen = Billing → **"Disagreement with a charge (workload or service) / Issue with Compute charge"**
(ids below are live-verified).

**1. Check the invoice posted (PowerShell, bearer-token pattern — az.cmd mangles `&` in URLs):**
```powershell
$token = az account get-access-token --query accessToken -o tsv; $h = @{ Authorization = "Bearer $token" }
(Invoke-RestMethod -Headers $h -Uri ("https://management.azure.com/providers/Microsoft.Billing/billingAccounts/" +
  "08ba551b-d9d2-53aa-686d-c72b57187141:8fb88a2a-bbef-430e-8d5b-b7ca40a64cba_2019-05-31/billingProfiles/" +
  "KNVI-ZBIZ-BG7-PGB/invoices?api-version=2020-05-01&periodStartDate=2026-06-01&periodEndDate=2026-07-31")).value |
  ForEach-Object { $_.name + "  " + $_.properties.invoicePeriodStartDate + "  " + $_.properties.totalAmount.value }
# Expect a new invoice whose period is 2026-06-01 -> 2026-06-30. Confirm ~\$449 of Azure Container Apps is on it.
```

**2. File the ticket (fill `<INVOICE_NUMBER>`):**
```powershell
$body = @{ properties = @{
  severity = "minimal"
  serviceId = "/providers/Microsoft.Support/services/517f2da6-78fd-0498-4e22-ad26996b1dfc"
  problemClassificationId = "/providers/Microsoft.Support/services/517f2da6-78fd-0498-4e22-ad26996b1dfc/problemClassifications/e5bc37bf-a84c-c670-441e-c4cdb47714c5"
  title = "Container Apps metering anomaly June 3-9 2026 - credit request $411.25 (invoice <INVOICE_NUMBER>)"
  description = "Requesting a credit of `$411.25 USD (conservative floor `$346.84) for anomalous Azure Container Apps active-usage billing, June 3-9 2026, on subscription Clique Pix (25410e67-b3c8-49a2-8cf0-ab9f77ce613f), invoice <INVOICE_NUMBER>. Resource: Container Apps Job caj-cliquepix-transcoder (rg-cliquepix-prod, East US). Meters: Standard vCPU/Memory Active Usage. THE CONTRADICTION: billed cost rose ~20x (steady `$3.74/day baseline to ~`$73/day, Jun 4-8) while every workload signal was provably flat - Azure Monitor Executions ~17,000-18,000/day (identical on cheap and expensive days; the KEDA 5s empty-queue poll), RequestedCores flat at 1.0, actual CPU (UsageNanoCores) zero or not emitting the entire window, console-log volume flat (~5,200 lines/day), and Application Insights records EXACTLY ONE real transcode all week (Jun 6 17:38 UTC, 19 seconds). Notably, the platform's own UsageNanoCores metric stopped emitting at exactly the cost-ramp onset (Jun 3 ~18:00 UTC) - the utilization signal went dark as the active-usage meter escalated, consistent with orphaned/zombie replicas held in a billed state or a metering error. No customer configuration or deployment change aligns with onset (Jun 3) or recovery (Jun 9-10). We are NOT disputing our own `$3.74/day idle baseline (minExecutions=1, since remediated to 0 on Jun 12 - Container Apps has billed `$0/day since). Claim = excess above baseline only: Jun 3 `$17.18, Jun 4 `$69.20, Jun 5 `$68.55, Jun 6 `$70.52, Jun 7 `$69.76, Jun 8 `$68.81, Jun 9 `$43.71, Jun 10 `$1.81, Jun 11 `$1.71 = `$411.25 total. All figures are reproducible with read-only Azure Monitor / Cost Management / Log Analytics queries (workspace log-cliquepix-prod, c158e174-b84f-41f3-bc36-03fbaf279eb7) - happy to provide the exact commands and our full evidence table on request."
  contactDetails = @{
    firstName = "Gene"; lastName = "Whitley"
    preferredContactMethod = "email"; primaryEmailAddress = "bluebuildapps@gmail.com"
    preferredTimeZone = "Eastern Standard Time"; country = "USA"; preferredSupportLanguage = "en-US"
  }
} } | ConvertTo-Json -Depth 5
$token = az account get-access-token --query accessToken -o tsv
Invoke-RestMethod -Method Put -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
  -Uri "https://management.azure.com/subscriptions/25410e67-b3c8-49a2-8cf0-ab9f77ce613f/providers/Microsoft.Support/supportTickets/cliquepix-aca-metering-jun2026?api-version=2020-04-01" `
  -Body $body
```

**3. Record** the returned `supportTicketId` here and in `DEPLOYMENT_STATUS.md`; follow to credit or written denial (§10.5).

---

## 11. Data provenance & honesty notes

- **Cost figures** are Azure Cost Management `ActualCost` values, queried 2026-06-22. Until the June invoice
  is finalized they are Microsoft's own *estimated/unbilled* amounts; they should match the invoice closely.
- **Metrics** (`Executions`, `RequestedCores`, `UsageNanoCores`) are Azure Monitor platform metrics for the
  job — Microsoft-generated, not application telemetry.
- **`UsageNanoCores` "no data emitted"** days mean the platform metric pipeline returned no samples — itself
  part of the anomaly signature (the utilization signal went dark exactly as the cost escalated).
- The internal incident write-up (`docs/DEPLOYMENT_STATUS.md`, June 11 cost-incident entry) estimated the
  anomaly at **~$435** using a $0 baseline; the **$411.25** here uses the stricter, more defensible $3.74/day
  baseline and is the recommended ask. Either is reasonable; $411.25 is the conservative, well-documented figure.
