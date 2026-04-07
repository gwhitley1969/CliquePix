# Video Infrastructure Runbook

## What this is

This is the as-built runbook for the new Azure infrastructure provisioned for Clique Pix video v1. It documents the exact `az` CLI commands run, what they produced, and how to roll back if needed. Created as part of Phase 2 of the implementation plan; finalized after all resources were verified working.

**Until Bicep IaC exists for these resources (post-v1.5), this runbook is the source of truth.** If you make changes via Portal or CLI, update this file.

---

## Resources provisioned

| Resource | Name | SKU/Tier | Resource ID |
|---|---|---|---|
| Log Analytics Workspace | `log-cliquepix-prod` | PerGB2018 | `/subscriptions/25410e67-b3c8-49a2-8cf0-ab9f77ce613f/resourceGroups/rg-cliquepix-prod/providers/Microsoft.OperationalInsights/workspaces/log-cliquepix-prod` |
| Container Registry | `cracliquepix` | Standard | `/subscriptions/.../resourceGroups/rg-cliquepix-prod/providers/Microsoft.ContainerRegistry/registries/cracliquepix` (login server: `cracliquepix.azurecr.io`) |
| Storage Queue | `video-transcode-queue` (in `stcliquepixprod`) | — | (queue inside existing storage account) |
| Container Apps Environment | `cae-cliquepix-prod` | Consumption | `/subscriptions/.../resourceGroups/rg-cliquepix-prod/providers/Microsoft.App/managedEnvironments/cae-cliquepix-prod` |
| Container Apps Job | `caj-cliquepix-transcoder` | Consumption | `/subscriptions/.../resourceGroups/rg-cliquepix-prod/providers/Microsoft.App/jobs/caj-cliquepix-transcoder` |
| Budget Alert | `budget-cliquepix-video` | Cost / Monthly $50 | (resource group scoped) |

**Subscription:** `25410e67-b3c8-49a2-8cf0-ab9f77ce613f` (Clique Pix)
**Tenant:** `f7d64f40-c033-418d-a050-d2ef4a9845fe`
**Region:** East US

---

## Resource provider registrations required

These resource providers are now registered on the subscription. They had to be registered before any of the new resources could be created:

```bash
az provider register --namespace Microsoft.ContainerRegistry --wait
az provider register --namespace Microsoft.App --wait
```

`Microsoft.OperationalInsights` was already registered.

---

## Provisioning commands (as-run)

### 1. Log Analytics Workspace

```bash
az monitor log-analytics workspace create \
  --resource-group rg-cliquepix-prod \
  --workspace-name log-cliquepix-prod \
  --location eastus
```

The workspace receives logs from the Container Apps Environment. SKU `PerGB2018` is the standard pay-per-GB tier.

### 2. Azure Container Registry (Standard SKU)

```bash
az acr create \
  --resource-group rg-cliquepix-prod \
  --name cracliquepix \
  --sku Standard \
  --location eastus
```

Standard SKU was chosen over Basic for throughput headroom (3x ReadOps/min) and 10x storage (100 GB vs 10 GB). See `docs/VIDEO_ARCHITECTURE_DECISIONS.md` Decision 0 — "ACR SKU selection" subsection.

### 3. Storage Queue (`video-transcode-queue`)

```bash
az storage queue create \
  --name video-transcode-queue \
  --account-name stcliquepixprod \
  --auth-mode login
```

`--auth-mode login` uses AAD authentication, which works whether or not shared key access is enabled on the storage account.

**Known drift from CLAUDE.md:** As of 2026-04-07, `allowSharedKeyAccess` on `stcliquepixprod` is `True`, even though CLAUDE.md says it should be `false`. This is a v1.5 audit and cleanup item — disable shared key access only after verifying no code paths still depend on it.

### 4. Container Apps Environment

```bash
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  -g rg-cliquepix-prod -n log-cliquepix-prod --query customerId -o tsv)
WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
  -g rg-cliquepix-prod -n log-cliquepix-prod --query primarySharedKey -o tsv)

az containerapp env create \
  --name cae-cliquepix-prod \
  --resource-group rg-cliquepix-prod \
  --location eastus \
  --logs-workspace-id "$WORKSPACE_ID" \
  --logs-workspace-key "$WORKSPACE_KEY"
```

Linked to Log Analytics workspace `log-cliquepix-prod` for log collection.

### 5. Container Apps Job (transcoder)

```bash
az containerapp job create \
  --name caj-cliquepix-transcoder \
  --resource-group rg-cliquepix-prod \
  --environment cae-cliquepix-prod \
  --trigger-type Event \
  --replica-timeout 900 \
  --replica-retry-limit 1 \
  --replica-completion-count 1 \
  --parallelism 1 \
  --min-executions 0 \
  --max-executions 10 \
  --polling-interval 30 \
  --image mcr.microsoft.com/azuredocs/aci-helloworld:latest \
  --cpu 2.0 \
  --memory 4.0Gi \
  --mi-system-assigned \
  --scale-rule-name azure-queue-scaler \
  --scale-rule-type azure-queue \
  --scale-rule-metadata "queueName=video-transcode-queue" "accountName=stcliquepixprod" "queueLength=1" \
  --scale-rule-auth "identity=system"
```

**Image is a placeholder** (`aci-helloworld`). Phase 3 builds and pushes the real FFmpeg transcoder image and updates the job to use it.

**Key parameters:**
- `--trigger-type Event` — KEDA scaler-based triggering
- `--replica-timeout 900` — kill any replica running longer than 15 minutes
- `--replica-retry-limit 1` — retry once before giving up to the poison queue
- `--max-executions 10` — never run more than 10 transcoder replicas in parallel
- `--cpu 2.0 --memory 4.0Gi` — generous resource allocation for FFmpeg
- `--mi-system-assigned` — system-assigned managed identity for AAD auth
- `--scale-rule-auth "identity=system"` — KEDA queue scaler uses the job's MI to poll the queue (no connection string)

**Captured principal ID:** `3bf7c2c1-8c34-4a12-adcd-d68e1485f4d8` (used in RBAC role assignments below)

### 6. Budget alert ($50/month)

```bash
az consumption budget create-with-rg \
  --resource-group rg-cliquepix-prod \
  --budget-name budget-cliquepix-video \
  --amount 50 \
  --category Cost \
  --time-grain Monthly \
  --time-period "{startDate:2026-04-01,endDate:2027-04-01}" \
  --notifications '{"Actual_GreaterThan_80_Percent":{"enabled":true,"operator":"GreaterThan","threshold":80,"contactEmails":["bluebuildapps@gmail.com"]}}'
```

Notification fires when actual spend exceeds 80% of $50 ($40) for the month, sent to `bluebuildapps@gmail.com`.

**Note:** the `az consumption budget create` command (without `-with-rg`) does NOT support inline notifications and was rejected. Use `create-with-rg` for notification support.

---

## RBAC role assignments

### Function App MI (`func-cliquepix-fresh`, principal `0929f2c6-659a-439c-85ea-92e050d2f763`)

| Role | Scope | Purpose |
|---|---|---|
| `Storage Queue Data Contributor` | storage account | Enqueue transcoder jobs on `video-transcode-queue` |
| `Storage Blob Data Contributor` | storage account | (existing — server-side blob operations) |
| `Storage Blob Delegator` | storage account | (existing — User Delegation SAS generation) |

### Container Apps Job MI (`caj-cliquepix-transcoder`, principal `3bf7c2c1-8c34-4a12-adcd-d68e1485f4d8`)

| Role | Scope | Purpose |
|---|---|---|
| `Storage Blob Data Contributor` | storage account | Read video originals, write HLS segments, MP4 fallback, poster |
| `Storage Queue Data Message Processor` | storage account | Dequeue and process transcoding jobs |
| `Storage Queue Data Reader` | storage account | KEDA scaler queue length polling |
| `AcrPull` | ACR | Pull the transcoder container image |

### Critical CLI bug workaround

**`az role assignment create` is broken in Azure CLI 2.77.0** for this subscription/tenant combination. It returns `ERROR: (MissingSubscription)` even with explicit `--subscription` and full resource paths.

**Workaround:** create role assignments via REST API directly. Example:

```bash
ASSIGNMENT_ID=$(python -c "import uuid; print(uuid.uuid4())")
SUB="25410e67-b3c8-49a2-8cf0-ab9f77ce613f"
SCOPE="/subscriptions/${SUB}/resourceGroups/rg-cliquepix-prod/providers/Microsoft.Storage/storageAccounts/stcliquepixprod"
ROLE_DEF_ID="974c5e8b-45b9-4653-ba55-5f855dd0fb88"  # Storage Queue Data Contributor
PRINCIPAL_ID="0929f2c6-659a-439c-85ea-92e050d2f763"  # Function App MI

az rest --method put \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignments/${ASSIGNMENT_ID}?api-version=2022-04-01" \
  --body "{\"properties\":{\"roleDefinitionId\":\"/subscriptions/${SUB}/providers/Microsoft.Authorization/roleDefinitions/${ROLE_DEF_ID}\",\"principalId\":\"${PRINCIPAL_ID}\",\"principalType\":\"ServicePrincipal\"}}"
```

Re-test `az role assignment create` after upgrading the CLI. If the bug is fixed in a later version, future role assignments can use the simpler CLI command.

### Role definition IDs (for future REST API calls)

| Role | ID |
|---|---|
| Storage Queue Data Contributor | `974c5e8b-45b9-4653-ba55-5f855dd0fb88` |
| Storage Blob Data Contributor | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` |
| Storage Blob Delegator | `db58b8e5-c6ad-4a2a-8342-4190687cbf4a` |
| Storage Queue Data Message Processor | `8a0f0c08-91a1-4084-bc3d-661d67233fed` |
| Storage Queue Data Reader | `19e7f393-937e-4f77-808e-94535e297925` |
| AcrPull | `7f951dda-4ed3-4680-a7ca-43fe172d538d` |

---

## Environment variables

### Container Apps Job (`caj-cliquepix-transcoder`)

```bash
az containerapp job update \
  --name caj-cliquepix-transcoder \
  --resource-group rg-cliquepix-prod \
  --set-env-vars \
    "STORAGE_ACCOUNT_NAME=stcliquepixprod" \
    "STORAGE_QUEUE_NAME=video-transcode-queue" \
    "BLOB_CONTAINER_NAME=photos" \
    "FUNCTION_CALLBACK_URL=https://func-cliquepix-fresh.azurewebsites.net/api/internal/video-processing-complete" \
    "FUNCTION_APP_AUDIENCE=api://func-cliquepix-fresh" \
    "APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string"
```

The App Insights connection string is sensitive and stored as a secret:

```bash
APPINSIGHTS_CONN=$(az functionapp config appsettings list -n func-cliquepix-fresh -g rg-cliquepix-prod \
  --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value" -o tsv)
az containerapp job secret set \
  --name caj-cliquepix-transcoder \
  --resource-group rg-cliquepix-prod \
  --secrets "appinsights-connection-string=$APPINSIGHTS_CONN"
```

### Function App (`func-cliquepix-fresh`) — new env vars added in Phase 2

```bash
az functionapp config appsettings set \
  --name func-cliquepix-fresh \
  --resource-group rg-cliquepix-prod \
  --settings \
    "STORAGE_QUEUE_NAME=video-transcode-queue" \
    "TRANSCODER_MI_PRINCIPAL_ID=3bf7c2c1-8c34-4a12-adcd-d68e1485f4d8" \
    "FUNCTION_APP_AUDIENCE=api://func-cliquepix-fresh"
```

`STORAGE_ACCOUNT_NAME` already existed. `WEB_PUBSUB_CONNECTION_STRING` already existed for DMs.

`TRANSCODER_MI_PRINCIPAL_ID` is used by `validateInternalCallerIdentity` (in Phase 4) to verify that callbacks to `/api/internal/video-processing-complete` are coming from the transcoder's managed identity.

`FUNCTION_APP_AUDIENCE` is used by the same validation function to check the JWT audience claim.

---

## Verification commands

After provisioning, verify everything is in place:

```bash
# Resources exist
az acr show --name cracliquepix --query "{sku:sku.name, loginServer:loginServer}" -o table
az containerapp env show --name cae-cliquepix-prod -g rg-cliquepix-prod --query "{name:name, location:location}" -o table
az containerapp job show --name caj-cliquepix-transcoder -g rg-cliquepix-prod --query "{trigger:properties.configuration.triggerType, image:properties.template.containers[0].image}" -o table
az storage queue exists --name video-transcode-queue --account-name stcliquepixprod --auth-mode login

# Budget exists
az consumption budget show --budget-name budget-cliquepix-video -g rg-cliquepix-prod --query "{amount:amount, timeGrain:timeGrain}" -o table

# RBAC roles (use REST since CLI is broken)
az rest --method get --url "https://management.azure.com/subscriptions/25410e67-b3c8-49a2-8cf0-ab9f77ce613f/resourceGroups/rg-cliquepix-prod/providers/Microsoft.Storage/storageAccounts/stcliquepixprod/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=atScope()" --query "value[?properties.principalId == '3bf7c2c1-8c34-4a12-adcd-d68e1485f4d8' || properties.principalId == '0929f2c6-659a-439c-85ea-92e050d2f763'].{principalId:properties.principalId, roleDefId:properties.roleDefinitionId}" -o table

# Function App env vars
az functionapp config appsettings list -n func-cliquepix-fresh -g rg-cliquepix-prod \
  --query "[?name=='STORAGE_QUEUE_NAME' || name=='TRANSCODER_MI_PRINCIPAL_ID' || name=='FUNCTION_APP_AUDIENCE'].{name:name, value:value}" -o table

# Container Apps Job env vars
az containerapp job show -n caj-cliquepix-transcoder -g rg-cliquepix-prod \
  --query "properties.template.containers[0].env[].name" -o tsv
```

---

## Rollback (full teardown)

If everything needs to come down (architecture decision reversed, project cancelled, etc.), apply in reverse dependency order:

```bash
# 1. Container Apps Job
az containerapp job delete --name caj-cliquepix-transcoder --resource-group rg-cliquepix-prod --yes

# 2. Container Apps Environment
az containerapp env delete --name cae-cliquepix-prod --resource-group rg-cliquepix-prod --yes

# 3. Container Registry (deletes all hosted images)
az acr delete --name cracliquepix --resource-group rg-cliquepix-prod --yes

# 4. Storage Queue (just the queue, not the storage account)
az storage queue delete --name video-transcode-queue --account-name stcliquepixprod --auth-mode login

# 5. Budget
az consumption budget delete --budget-name budget-cliquepix-video -g rg-cliquepix-prod

# 6. Log Analytics workspace (only if no other workloads use it)
az monitor log-analytics workspace delete --workspace-name log-cliquepix-prod -g rg-cliquepix-prod --yes

# 7. Remove Function App env vars
az functionapp config appsettings delete --name func-cliquepix-fresh -g rg-cliquepix-prod \
  --setting-names "STORAGE_QUEUE_NAME" "TRANSCODER_MI_PRINCIPAL_ID" "FUNCTION_APP_AUDIENCE"

# 8. Remove RBAC role assignments (use REST API workaround)
# Get the assignment IDs first via REST query, then DELETE each one
```

**Database migration rollback** is separate — see `backend/src/shared/db/migrations/007_rollback.sql`.

---

## Cost estimate at MVP scale

| Resource | Monthly cost |
|---|---|
| Log Analytics workspace | ~$2-5 (depends on log volume) |
| ACR Standard | ~$20 (fixed) |
| Container Apps Environment | $0 (consumption-only billing) |
| Container Apps Job | ~$3-15 (per-vCPU-second of actual transcoding) |
| Storage Queue | ~$0.05 (per million transactions) |
| Budget alert | $0 |
| **Total** | **~$25-40/month** at MVP scale (~100 videos/month × 5 min each) |

This is well under the $50/month budget alert threshold. Daily cost during dev should stay under $1.

---

## Outstanding follow-ups

- **CLI bug:** Re-test `az role assignment create` after upgrading Azure CLI from 2.77.0
- **Storage account:** Audit code paths and disable `allowSharedKeyAccess` (CLAUDE.md says it should be `false`)
- **Function App:** Migrate from Node 20 to Node 24 before 2026-04-30 (Node 20 EOL)
- **Bicep IaC:** Convert this runbook to Bicep templates in v1.5
- **Sample test videos:** Create the `dev-assets` blob container and upload reference videos for the `download-sample-videos.sh` script (Phase 3)
