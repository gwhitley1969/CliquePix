# Azure Infrastructure Deployment Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision all remaining Azure resources, configure existing ones, deploy the backend, and make the API reachable via Front Door → APIM → Function App.

**Architecture:** Direct CLI deployment using `az` commands. Resources are created in dependency order: Log Analytics → App Insights → Function App → RBAC → Storage config → Database → Key Vault secrets → Function App settings → Deploy code → APIM import → Front Door → DNS. No Bicep/Terraform.

**Tech Stack:** Azure CLI, Azure Functions Core Tools, PostgreSQL 18, Node.js 20

---

## Existing Resources (verified)

| Resource | Name | Location | Status |
|----------|------|----------|--------|
| Resource Group | `rg-cliquepix-prod` | eastus | Ready |
| Storage Account | `stcliquepixprod` | eastus | Ready — `allowSharedKeyAccess: true` needs fixing |
| PostgreSQL | `pg-cliquepixdb` | eastus2 | Ready — v18, Burstable B1ms, no app DB yet |
| Key Vault | `kv-cliquepix-prod` | eastus | Ready — needs secrets |
| APIM | `apim-cliquepix-002` | eastus | Ready — Developer SKU, needs API import |
| DNS Zone | `clique-pix.com` | global | Ready |
| Entra External ID | `cliquepix.onmicrosoft.com` | — | Exists — needs app registration |

## Resources to Create

| Resource | Name | Location |
|----------|------|----------|
| Log Analytics Workspace | `log-cliquepix-prod` | eastus |
| Application Insights | `appi-cliquepix-prod` | eastus |
| Function App + Plan | `func-cliquepix-fresh` | eastus |
| Front Door (Standard) | `fd-cliquepix-prod` | global |

---

### Task 1: Create Log Analytics Workspace

- [ ] **Step 1: Create the workspace**

```bash
az monitor log-analytics workspace create \
  --resource-group rg-cliquepix-prod \
  --workspace-name log-cliquepix-prod \
  --location eastus \
  --sku PerGB2018
```

- [ ] **Step 2: Verify creation**

```bash
az monitor log-analytics workspace show \
  --resource-group rg-cliquepix-prod \
  --workspace-name log-cliquepix-prod \
  --query "{name:name, id:id}" -o table
```

---

### Task 2: Create Application Insights (workspace-based)

- [ ] **Step 1: Get Log Analytics workspace ID**

```bash
LOG_WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-cliquepix-prod \
  --workspace-name log-cliquepix-prod \
  --query id -o tsv)
```

- [ ] **Step 2: Create Application Insights**

```bash
az monitor app-insights component create \
  --app appi-cliquepix-prod \
  --resource-group rg-cliquepix-prod \
  --location eastus \
  --kind web \
  --application-type web \
  --workspace "$LOG_WORKSPACE_ID"
```

- [ ] **Step 3: Capture the connection string**

```bash
APPINSIGHTS_CS=$(az monitor app-insights component show \
  --app appi-cliquepix-prod \
  --resource-group rg-cliquepix-prod \
  --query connectionString -o tsv)
echo "App Insights Connection String: $APPINSIGHTS_CS"
```

---

### Task 3: Create Function App (Flex Consumption, Node.js 20, Linux)

- [ ] **Step 1: Create the Function App**

```bash
az functionapp create \
  --resource-group rg-cliquepix-prod \
  --name func-cliquepix-fresh \
  --storage-account stcliquepixprod \
  --runtime node \
  --runtime-version 20 \
  --os-type Linux \
  --functions-version 4 \
  --consumption-plan-location eastus
```

Note: If Flex Consumption is available in the region, use `--flexconsumption-location eastus` instead. If not available, standard Consumption plan is acceptable for v1.

- [ ] **Step 2: Enable system-assigned managed identity**

```bash
az functionapp identity assign \
  --resource-group rg-cliquepix-prod \
  --name func-cliquepix-fresh
```

- [ ] **Step 3: Capture the managed identity principal ID**

```bash
FUNC_PRINCIPAL_ID=$(az functionapp identity show \
  --resource-group rg-cliquepix-prod \
  --name func-cliquepix-fresh \
  --query principalId -o tsv)
echo "Function App Principal ID: $FUNC_PRINCIPAL_ID"
```

---

### Task 4: Assign RBAC Roles to Function App Managed Identity

- [ ] **Step 1: Get resource IDs**

```bash
STORAGE_ID=$(az storage account show --name stcliquepixprod --resource-group rg-cliquepix-prod --query id -o tsv)
KV_ID=$(az keyvault show --name kv-cliquepix-prod --resource-group rg-cliquepix-prod --query id -o tsv)
FUNC_PRINCIPAL_ID=$(az functionapp identity show --resource-group rg-cliquepix-prod --name func-cliquepix-fresh --query principalId -o tsv)
```

- [ ] **Step 2: Assign Storage Blob Data Contributor**

```bash
az role assignment create \
  --assignee "$FUNC_PRINCIPAL_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_ID"
```

- [ ] **Step 3: Assign Storage Blob Delegator**

```bash
az role assignment create \
  --assignee "$FUNC_PRINCIPAL_ID" \
  --role "Storage Blob Delegator" \
  --scope "$STORAGE_ID"
```

- [ ] **Step 4: Assign Key Vault Secrets User**

```bash
az role assignment create \
  --assignee "$FUNC_PRINCIPAL_ID" \
  --role "Key Vault Secrets User" \
  --scope "$KV_ID"
```

- [ ] **Step 5: Verify all role assignments**

```bash
az role assignment list \
  --assignee "$FUNC_PRINCIPAL_ID" \
  --query "[].{Role:roleDefinitionName, Scope:scope}" -o table
```

---

### Task 5: Configure Storage Account

- [ ] **Step 1: Disable shared key access**

```bash
az storage account update \
  --name stcliquepixprod \
  --resource-group rg-cliquepix-prod \
  --allow-shared-key-access false
```

- [ ] **Step 2: Create the `photos` container (private access)**

```bash
az storage container create \
  --name photos \
  --account-name stcliquepixprod \
  --auth-mode login \
  --public-access off
```

- [ ] **Step 3: Verify**

```bash
az storage account show --name stcliquepixprod --resource-group rg-cliquepix-prod \
  --query "{allowSharedKeyAccess:allowSharedKeyAccess, allowBlobPublicAccess:allowBlobPublicAccess}" -o table
az storage container list --account-name stcliquepixprod --auth-mode login \
  --query "[].{Name:name}" -o table
```

---

### Task 6: Create PostgreSQL Database and Run Schema Migration

- [ ] **Step 1: Create the cliquepix database**

```bash
az postgres flexible-server db create \
  --resource-group rg-cliquepix-prod \
  --server-name pg-cliquepixdb \
  --database-name cliquepix
```

- [ ] **Step 2: Run the schema migration**

Requires `psql` client. Connect and run the migration SQL:

```bash
psql "host=pg-cliquepixdb.postgres.database.azure.com port=5432 dbname=cliquepix user=<admin-username> password=<admin-password> sslmode=require" \
  -f backend/src/shared/db/migrations/001_initial_schema.sql
```

Note: The admin username and password were set when the PostgreSQL server was created. If unknown, check the Azure Portal or use `az postgres flexible-server show` to get the admin username, then reset the password if needed:

```bash
# Get admin username
az postgres flexible-server show --name pg-cliquepixdb --resource-group rg-cliquepix-prod --query administratorLogin -o tsv

# Reset password if needed (will prompt)
az postgres flexible-server update --name pg-cliquepixdb --resource-group rg-cliquepix-prod --admin-password <new-password>
```

- [ ] **Step 3: Verify tables were created**

```bash
psql "host=pg-cliquepixdb.postgres.database.azure.com port=5432 dbname=cliquepix user=<admin-username> password=<admin-password> sslmode=require" \
  -c "\dt"
```

Expected: 8 tables (users, circles, circle_members, events, photos, reactions, push_tokens, notifications)

---

### Task 7: Configure Key Vault Secrets

- [ ] **Step 1: Grant yourself Key Vault Secrets Officer role (if not already assigned)**

```bash
USER_OID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
  --assignee "$USER_OID" \
  --role "Key Vault Secrets Officer" \
  --scope "$KV_ID"
```

- [ ] **Step 2: Store PostgreSQL connection string**

```bash
az keyvault secret set \
  --vault-name kv-cliquepix-prod \
  --name pg-connection-string \
  --value "postgresql://<admin-username>:<password>@pg-cliquepixdb.postgres.database.azure.com:5432/cliquepix?sslmode=require"
```

- [ ] **Step 3: Store FCM credentials (after Firebase project is created)**

```bash
az keyvault secret set \
  --vault-name kv-cliquepix-prod \
  --name fcm-credentials \
  --value '<JSON service account key from Firebase>'
```

Note: This step depends on Firebase project creation (Task 11). Can be done later.

---

### Task 8: Configure Function App Settings

- [ ] **Step 1: Get Key Vault secret URIs**

```bash
PG_SECRET_URI=$(az keyvault secret show --vault-name kv-cliquepix-prod --name pg-connection-string --query id -o tsv)
APPINSIGHTS_CS=$(az monitor app-insights component show --app appi-cliquepix-prod --resource-group rg-cliquepix-prod --query connectionString -o tsv)
```

- [ ] **Step 2: Set all app settings**

```bash
az functionapp config appsettings set \
  --resource-group rg-cliquepix-prod \
  --name func-cliquepix-fresh \
  --settings \
    "PG_CONNECTION_STRING=@Microsoft.KeyVault(SecretUri=${PG_SECRET_URI})" \
    "STORAGE_ACCOUNT_NAME=stcliquepixprod" \
    "ENTRA_TENANT_ID=<your-entra-tenant-id>" \
    "ENTRA_CLIENT_ID=<your-entra-client-id>" \
    "APPLICATIONINSIGHTS_CONNECTION_STRING=${APPINSIGHTS_CS}" \
    "FUNCTIONS_WORKER_RUNTIME=node" \
    "NODE_ENV=production"
```

Note: Replace `<your-entra-tenant-id>` and `<your-entra-client-id>` with values from the Entra External ID app registration (Task 11).

---

### Task 9: Deploy Backend Code to Function App

- [ ] **Step 1: Build the TypeScript project**

```bash
cd backend
npm run build
```

- [ ] **Step 2: Deploy to Azure**

```bash
func azure functionapp publish func-cliquepix-fresh
```

Or using az CLI:

```bash
cd backend
zip -r ../deploy.zip . -x "node_modules/.cache/*" "src/*" ".git/*"
az functionapp deployment source config-zip \
  --resource-group rg-cliquepix-prod \
  --name func-cliquepix-fresh \
  --src ../deploy.zip
```

- [ ] **Step 3: Verify the health endpoint**

```bash
FUNC_URL=$(az functionapp show --resource-group rg-cliquepix-prod --name func-cliquepix-fresh --query defaultHostName -o tsv)
curl -s "https://${FUNC_URL}/api/health" | jq .
```

Expected: `{ "data": { "status": "healthy", "timestamp": "..." }, "error": null }`

---

### Task 10: Configure APIM — Import API and Set Policies

- [ ] **Step 1: Get the Function App URL**

```bash
FUNC_HOST=$(az functionapp show --resource-group rg-cliquepix-prod --name func-cliquepix-fresh --query defaultHostName -o tsv)
echo "Backend URL: https://${FUNC_HOST}"
```

- [ ] **Step 2: Import the API into APIM**

Create an OpenAPI spec or import directly. For simplicity, create a blank API and add operations manually, or use the Function App auto-import:

```bash
az apim api import \
  --resource-group rg-cliquepix-prod \
  --service-name apim-cliquepix-002 \
  --api-id cliquepix-v1 \
  --path "" \
  --display-name "CliquePix API v1" \
  --service-url "https://${FUNC_HOST}/api" \
  --protocols https \
  --specification-format OpenApi \
  --specification-path backend/api-spec.json
```

If no OpenAPI spec exists, create the API manually and set the backend:

```bash
az apim api create \
  --resource-group rg-cliquepix-prod \
  --service-name apim-cliquepix-002 \
  --api-id cliquepix-v1 \
  --path "api" \
  --display-name "CliquePix API v1" \
  --service-url "https://${FUNC_HOST}/api" \
  --protocols https \
  --subscription-required false
```

- [ ] **Step 3: Add a wildcard pass-through operation**

```bash
az apim api operation create \
  --resource-group rg-cliquepix-prod \
  --service-name apim-cliquepix-002 \
  --api-id cliquepix-v1 \
  --operation-id catch-all-get \
  --display-name "GET catch-all" \
  --method GET \
  --url-template "/*"

az apim api operation create \
  --resource-group rg-cliquepix-prod \
  --service-name apim-cliquepix-002 \
  --api-id cliquepix-v1 \
  --operation-id catch-all-post \
  --display-name "POST catch-all" \
  --method POST \
  --url-template "/*"

az apim api operation create \
  --resource-group rg-cliquepix-prod \
  --service-name apim-cliquepix-002 \
  --api-id cliquepix-v1 \
  --operation-id catch-all-delete \
  --display-name "DELETE catch-all" \
  --method DELETE \
  --url-template "/*"

az apim api operation create \
  --resource-group rg-cliquepix-prod \
  --service-name apim-cliquepix-002 \
  --api-id cliquepix-v1 \
  --operation-id catch-all-patch \
  --display-name "PATCH catch-all" \
  --method PATCH \
  --url-template "/*"
```

- [ ] **Step 4: Test through APIM**

```bash
APIM_URL="https://apim-cliquepix-002.azure-api.net"
curl -s "${APIM_URL}/api/health" | jq .
```

---

### Task 11: Create Front Door (Standard, No WAF)

- [ ] **Step 1: Create the Front Door profile**

```bash
az afd profile create \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --sku Standard_AzureFrontDoor
```

- [ ] **Step 2: Create the endpoint**

```bash
az afd endpoint create \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --endpoint-name cliquepix-api \
  --enabled-state Enabled
```

- [ ] **Step 3: Create the origin group**

```bash
az afd origin-group create \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --origin-group-name apim-origin-group \
  --probe-request-type GET \
  --probe-protocol Https \
  --probe-path "/api/health" \
  --probe-interval-in-seconds 30 \
  --sample-size 4 \
  --successful-samples-required 3
```

- [ ] **Step 4: Create the origin (pointing to APIM)**

```bash
az afd origin create \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --origin-group-name apim-origin-group \
  --origin-name apim-origin \
  --host-name apim-cliquepix-002.azure-api.net \
  --origin-host-header apim-cliquepix-002.azure-api.net \
  --http-port 80 \
  --https-port 443 \
  --priority 1 \
  --weight 1000 \
  --enabled-state Enabled
```

- [ ] **Step 5: Create the route**

```bash
az afd route create \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --endpoint-name cliquepix-api \
  --route-name default-route \
  --origin-group apim-origin-group \
  --supported-protocols Https \
  --forwarding-protocol HttpsOnly \
  --patterns-to-match "/*" \
  --https-redirect Enabled
```

- [ ] **Step 6: Get the Front Door endpoint FQDN**

```bash
FD_FQDN=$(az afd endpoint show \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --endpoint-name cliquepix-api \
  --query hostName -o tsv)
echo "Front Door FQDN: https://${FD_FQDN}"
```

- [ ] **Step 7: Test through Front Door**

```bash
curl -s "https://${FD_FQDN}/api/health" | jq .
```

---

### Task 12: Configure DNS — Custom Domain for API

- [ ] **Step 1: Create CNAME record for api.clique-pix.com**

```bash
FD_FQDN=$(az afd endpoint show --resource-group rg-cliquepix-prod --profile-name fd-cliquepix-prod --endpoint-name cliquepix-api --query hostName -o tsv)

az network dns record-set cname set-record \
  --resource-group rg-cliquepix-prod \
  --zone-name clique-pix.com \
  --record-set-name api \
  --cname "$FD_FQDN"
```

- [ ] **Step 2: Add custom domain to Front Door**

```bash
az afd custom-domain create \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --custom-domain-name api-clique-pix \
  --host-name api.clique-pix.com \
  --certificate-type ManagedCertificate \
  --minimum-tls-version TLS12
```

- [ ] **Step 3: Associate custom domain with the route**

```bash
az afd route update \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --endpoint-name cliquepix-api \
  --route-name default-route \
  --custom-domains api-clique-pix
```

- [ ] **Step 4: Wait for domain validation and certificate provisioning**

```bash
az afd custom-domain show \
  --resource-group rg-cliquepix-prod \
  --profile-name fd-cliquepix-prod \
  --custom-domain-name api-clique-pix \
  --query "{domainValidationState:domainValidationState, provisioningState:provisioningState}" -o table
```

- [ ] **Step 5: Test via custom domain**

```bash
curl -s "https://api.clique-pix.com/api/health" | jq .
```

---

### Task 13: Delete Old PostgreSQL Server

- [ ] **Step 1: Confirm pg-cliquepix has no app databases**

```bash
az postgres flexible-server db list --server-name pg-cliquepix --resource-group rg-cliquepix-prod --query "[].name" -o table
```

Expected: only system databases (azure_maintenance, postgres, azure_sys)

- [ ] **Step 2: Delete the old server**

```bash
az postgres flexible-server delete \
  --resource-group rg-cliquepix-prod \
  --name pg-cliquepix \
  --yes
```

---

### Task 14: Update DEPLOYMENT_STATUS.md

- [ ] **Step 1: Update the document to reflect completed infrastructure**

Update `docs/DEPLOYMENT_STATUS.md` with current status of all tasks.

- [ ] **Step 2: Commit and push**

```bash
git add docs/DEPLOYMENT_STATUS.md
git commit -m "docs: update deployment status after Azure provisioning"
git push origin main
```

---

## Post-Deployment: Manual Steps (Not CLI-Automatable)

These require the Azure Portal or separate tooling:

1. **Entra External ID App Registration** — Register CliquePix app in `cliquepix.onmicrosoft.com` tenant, configure email OTP, get tenant ID and client ID
2. **Firebase Project** — Create in Firebase Console, enable FCM, download `google-services.json` and `GoogleService-Info.plist`, export service account JSON for Key Vault
3. **APIM Rate Limiting Policies** — Configure via Portal or policy XML (global 60/min, uploads 10/min, auth 5/min)
4. **APIM X-Azure-FDID Validation** — Restrict APIM to only accept traffic from the Front Door instance
5. **Function App Network Restrictions** — Optionally restrict to only accept traffic from APIM
