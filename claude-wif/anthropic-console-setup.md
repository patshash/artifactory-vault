# Anthropic Console Setup (Manual Alternative)

Follow these steps in the [Claude Console](https://console.anthropic.com) to configure Workload Identity Federation.

## Prerequisites

- A Claude Organisation must be initially created for Individual Claude accounts. 
  - [Claude Console](https://console.anthropic.com) -> User -> Organisation Settings 
- Admin access to your Anthropic organization
- The Vault OIDC issuer URL (output from `vault-setup/`):
  ```bash
  terraform -chdir=vault-setup output vault_identity_token_issuer
  ```

## Step 1: Create a service account

1. Navigate to **User → Organization Settings -> Service Accounts**.
2. Click **Create service account**.
3. Name: `vault-wif` (or your preferred name).
4. Note the returned **`svac_...`** ID — you will need it in step 4.

## Step 2: Create a new Workspace and add the service account to the new workspace

1. Navigate to **User → Organization Settings -> Service Accounts**.
2. Click **Create Service Account** and add the `vault-wif` service account.
4. Navigate to **User → Organization Settings -> Workspaces**.
5. Click **Create Workspace** 
6. Enter a Name and Select Colour (eg: `wif-workspace`)
7. Select the new workspace (`wif-workspace`) where the service account should operate.
8. On the new screen in the workspace settings navigate to **Manage -> Service Accounts -> Add Service Account**
9. Select the new Service account and Assign the **Developer** role (`workspace_developer`).

## Step 3: Create a federation issuer

1. Navigate to **Organisation Settings → Workload identity**.
2. Click **Register issuer**.
3. Configure:
   - **Name**: `vault-sandpit`
   - **Issuer URL**: `https://vault.<your-zone>/v1/identity/oidc` (your Vault OIDC issuer URL)
   - **JWKS source**: `OIDC discovery` (default) — Anthropic will fetch `/.well-known/openid-configuration` from the Vault OIDC issuer
4. Save and note the returned **`fdis_...`** ID.

## Step 4: Create a federation rule

1. On the federation issuer you just created, click **New rule**.
2. Configure:
   - **Name**: `vault-claude-access`
   - **Issuer**: `vault-sandpit`
   - **Match conditions** (choose one):
     - **Option A - CEL Claims Match** (recommended)
       ```
       claims.metadata.claude_workspace == "wif-workspace"
       ```
     - **Option B — CEL condition** (matches all Vault entities):
       ```
       claims.iss == "https://vault.<your-zone>/v1/identity/oidc"
       ```
     - **Option C — Exact subject**: Use the Vault entity ID of the user/service that will
       authenticate (e.g., `810eb3f7-1e20-4098-5d09-c1747af563ba`). Find it with:
       `vault read -field=id identity/entity/name/<username>`
     - Audience: `https://api.anthropic.com`
   - **Target service account**: the `svac_...` ID from step 1
   - **Workspaces**: `wif-workspace` or `enable in all workspaces`
   - **OAuth scope**: `workspace:developer`
   - **Token lifetime**: `3600` seconds
3. Save and note the returned **`fdrl_...`** ID.

> **Workspace routing:** If the federation rule is enabled for more than one workspace,
> the token exchange request **must** include a `workspace_id` field. You can also route
> to a specific workspace via a CEL condition on Vault entity metadata — e.g.,
> `claims.metadata.claude_workspace == "wrkspc_..."` — by setting the metadata on
> the Vault entity with `vault write identity/entity/name/<user> metadata=claude_workspace=wrkspc_...`.

## Outputs needed for validation

After completing the steps above, you will need the following IDs for the validation script:

| Value | Example | Used by |
|---|---|---|
| Service account ID | `svac_01H...` | `--service-account-id` |
| Federation rule ID | `fdrl_01H...` | `--federation-rule-id` |
| Organization ID | `org_01H...` (visible in Settings → Organization) | `--organization-id` |

Create a JSON file at `claude-wif/anthropic-wif-ids.json` with the IDs for reference:

```json
{
  "service_account_id": "svac_...",
  "federation_issuer_id": "fdis_...",
  "federation_rule_id": "fdrl_..."
}
```

Then run the validation script:

```bash
export VAULT_ADDR="https://vault.example.com"
export VAULT_USERNAME="vault-claude-test-user"
export ANTHROPIC_ORGANIZATION_ID="org_..."
export ANTHROPIC_SERVICE_ACCOUNT_ID="svac_..."
export ANTHROPIC_FEDERATION_RULE_ID="fdrl_..."
export ANTHROPIC_WORKSPACE_ID="wrkspc_..."  # required when rule spans multiple workspaces

./scripts/validate-vault-claude.sh
```
