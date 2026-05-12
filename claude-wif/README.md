# Claude WIF — Vault Workload Identity Federation for Anthropic

This Terraform stack configures a Vault OIDC role that issues identity tokens for exchange with the Anthropic Claude API using [Workload Identity Federation](https://docs.anthropic.com/en/docs/build-with-claude/workload-identity-federation) (WIF). No static `sk-ant-...` API keys are required.

The pattern is the same as the existing JFrog integration: Vault acts as the OIDC identity provider, Anthropic is the relying party.

## How it works

1. A workload authenticates to Vault and receives a signed JWT from `identity/oidc/token/claude-token-role`.
2. The workload exchanges the JWT with Anthropic at `https://api.anthropic.com/v1/oauth/token` using the `jwt-bearer` grant type.
3. Anthropic verifies the JWT signature against the Vault JWKS, evaluates the federation rule, and returns a short-lived `sk-ant-oat01-...` access token.
4. The workload uses the access token to call the Claude Messages API.

## Prerequisites

- The `vault-setup/` stack must be applied first (provides the OIDC signing key and userpass auth mount).
- Vault must be publicly reachable over HTTPS so Anthropic can fetch the OIDC discovery and JWKS endpoints.
- An active Anthropic organization with WIF enabled.
- Admin access to the [Claude Console](https://console.anthropic.com) for WIF configuration.

## Setup

### 1. Configure Anthropic WIF (manual)

Follow the instructions in [`anthropic-console-setup.md`](anthropic-console-setup.md) to configure the service account, federation issuer, and federation rule in the Claude Console.

### 2. Create a local tfvars file

```bash
cp claude-wif/terraform.tfvars.example claude-wif/terraform.tfvars
```

Populate at least:

- `vault_addr` — your Vault URL
- `vault_token` — a Vault token with admin access

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

## Inputs

| Variable | Description | Default |
|---|---|---|
| `vault_addr` | Vault base URL | — |
| `vault_token` | Vault admin token | — |
| `vault_namespace` | Vault Enterprise namespace | `""` |
| `vault_setup_state_path` | Path to vault-setup state | `../vault-setup/terraform.tfstate` |
| `role_name` | OIDC role name | `claude-token-role` |
| `application_audience` | Token audience claim | `https://api.anthropic.com` |
| `token_ttl_seconds` | Token TTL | `3600` |
| `validation_username` | Test user name | `vault-claude-test-user` |

## Outputs

| Output | Description |
|---|---|
| `vault_identity_token_role_name` | OIDC role name |
| `vault_identity_token_audience` | Audience claim value |
| `vault_identity_token_endpoint` | Vault token endpoint URL |
| `vault_identity_token_issuer` | Vault OIDC issuer URL |
| `vault_identity_token_discovery_endpoint` | OIDC discovery URL |
| `vault_identity_token_jwks_endpoint` | JWKS endpoint URL |
| `validation_vault_username` | Test user name |
| `validation_vault_password` | Test user password (sensitive) |
