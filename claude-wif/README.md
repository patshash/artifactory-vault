# Claude WIF — Vault SPIFFE Secrets Engine for Anthropic Workload Identity Federation

This Terraform stack configures the Vault SPIFFE secrets engine to mint JWT-SVIDs for exchange with the Anthropic Claude API using [Workload Identity Federation](https://docs.anthropic.com/en/docs/build-with-claude/workload-identity-federation) (WIF). No static `sk-ant-...` API keys are required.

Unlike the identity token approach, the SPIFFE secrets engine provides a dedicated mount with its own signing key lifecycle, SPIFFE ID-based subject claims, and per-request audience specification.

## How it works

1. A workload authenticates to Vault and mints a JWT-SVID via `POST /v1/spiffe/role/claude-token-role/mintjwt` with `audience=https://api.anthropic.com`.
2. The workload exchanges the JWT-SVID with Anthropic at `https://api.anthropic.com/v1/oauth/token` using the `jwt-bearer` grant type.
3. Anthropic verifies the JWT signature against the SPIFFE engine's JWKS, evaluates the federation rule, and returns a short-lived `sk-ant-oat01-...` access token.
4. The workload uses the access token to call the Claude Messages API.

## Prerequisites

- The `vault-setup/` stack must be applied first (provides the userpass auth mount).
- Vault must be publicly reachable over HTTPS so Anthropic can fetch the OIDC discovery and JWKS endpoints from the SPIFFE mount.
- An active Anthropic organization with WIF enabled.
- Admin access to the [Claude Console](https://console.anthropic.com) for WIF configuration.

## Setup

### 1. Configure Anthropic WIF (manual)

Follow the instructions in [`anthropic-console-setup.md`](anthropic-console-setup.md) to configure the service account, federation issuer, and federation rule in the Claude Console.

**Important:** When configuring the federation issuer URL, use the SPIFFE engine's issuer:
```
https://vault.example.com/v1/spiffe
```

### 2. Create a local tfvars file

```bash
cp claude-wif/terraform.tfvars.example claude-wif/terraform.tfvars
```

Populate at least:

- `vault_addr` — your Vault URL
- `vault_token` — a Vault token with admin access
- `trust_domain` — your SPIFFE trust domain (e.g. `vault.example.com`)

### 3. Apply the stack

```bash
terraform -chdir=claude-wif init
terraform -chdir=claude-wif plan -out claude-wif.tfplan
terraform -chdir=claude-wif apply claude-wif.tfplan
```

### 4. Retrieve validation credentials

```bash
terraform -chdir=claude-wif output validation_vault_username
terraform -chdir=claude-wif output -raw validation_vault_password
```

## Validation

Run the end-to-end validation script:

```bash
export VAULT_ADDR="https://vault.example.com"
export VAULT_USERNAME="vault-claude-test-user"
export ANTHROPIC_ORGANIZATION_ID="org_..."
export ANTHROPIC_SERVICE_ACCOUNT_ID="svac_..."
export ANTHROPIC_FEDERATION_RULE_ID="fdrl_..."
export ANTHROPIC_WORKSPACE_ID="wrkspc_..."  # required when rule spans multiple workspaces

./scripts/validate-vault-claude.sh
```

See the [root README](../README.md) for full usage details and optional flags.

## Token shape (JWT-SVID)

```json
{
  "iss": "https://vault.example.com/v1/spiffe",
  "aud": "https://api.anthropic.com",
  "sub": "spiffe://vault.example.com/claude/vault-claude-test-user",
  "azp": "vault-claude-test-user",
  "metadata": { "claude_workspace": "wif-workspace" },
  "vault": { "entity": { "id": "<vault-entity-id>" } },
  "jti": "<unique-token-id>",
  "iat": 1715000000,
  "exp": 1715003600
}
```

## Inputs

| Variable | Description | Default |
|---|---|---|
| `vault_addr` | Vault base URL | — |
| `vault_token` | Vault admin token | — |
| `vault_namespace` | Vault Enterprise namespace | `""` |
| `vault_setup_state_path` | Path to vault-setup state | `../vault-setup/terraform.tfstate` |
| `spiffe_mount_path` | SPIFFE engine mount path | `spiffe` |
| `trust_domain` | SPIFFE trust domain | — |
| `jwt_issuer_base_url` | JWT issuer base URL | `""` (uses vault_addr) |
| `jwt_signing_algorithm` | Signing algorithm | `RS256` |
| `key_lifetime_seconds` | Key rotation period | `86400` |
| `role_name` | SPIFFE role name | `claude-token-role` |
| `application_audience` | Token audience claim | `https://api.anthropic.com` |
| `token_ttl_seconds` | Token TTL | `3600` |
| `validation_username` | Test user name | `vault-claude-test-user` |

## Outputs

| Output | Description |
|---|---|
| `spiffe_mount_path` | SPIFFE engine mount path |
| `spiffe_role_name` | SPIFFE role name |
| `spiffe_mintjwt_endpoint` | Vault mintjwt endpoint URL |
| `spiffe_jwt_audience` | Audience value for mintjwt |
| `spiffe_jwt_issuer` | JWT issuer URL |
| `spiffe_discovery_endpoint` | OIDC discovery URL |
| `spiffe_jwks_endpoint` | JWKS endpoint URL |
| `spiffe_trust_domain` | Configured trust domain |
| `validation_vault_username` | Test user name |
| `validation_vault_password` | Test user password (sensitive) |
