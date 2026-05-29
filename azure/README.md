# Azure Workload Identity Federation with Vault SPIFFE

This Terraform configuration provisions end-to-end **Workload Identity Federation (WIF)** between HashiCorp Vault and Microsoft Azure. Vault's SPIFFE secrets engine issues signed JWT-SVIDs that Azure accepts as federated credentials, allowing workloads to obtain Azure access tokens without storing secrets.

## How It Works

```
Workload → Vault (userpass auth) → JWT-SVID (SPIFFE) → Azure token exchange → Azure Storage API
```

1. A workload authenticates to Vault (e.g., userpass)
2. Vault mints a signed JWT-SVID with a SPIFFE ID subject and custom claims
3. The workload exchanges the JWT-SVID with Microsoft Entra ID for an Azure access token
4. The Azure access token is used to call Azure APIs (e.g., Storage)

## Prerequisites

- **Vault** 1.16+ with the SPIFFE secrets engine available
- **Vault setup state**: The `vault-setup/` stack must be applied first (provides the userpass auth mount accessor)
- **Azure subscription** with permissions to:
  - Read existing App Registrations
  - Create Federated Identity Credentials
  - Create Storage Accounts and assign RBAC roles
- **Terraform** >= 1.5.0

### Required Providers

| Provider | Version |
|----------|---------|
| `hashicorp/vault` | ~> 4.0 |
| `hashicorp/azuread` | ~> 3.0 |
| `hashicorp/azurerm` | ~> 4.0 |
| `hashicorp/random` | ~> 3.6 |

## Setup

1. **Apply the `vault-setup/` stack first** (if not already done):

   ```bash
   cd ../vault-setup
   terraform apply
   ```

2. **Create your `terraform.tfvars`** from the example:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Initialize and apply:**

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `vault_addr` | Vault server URL (e.g., `https://vault.example.com`) |
| `vault_token` | Vault token with admin privileges |
| `spiffe_trust_domain` | SPIFFE trust domain — typically the Vault FQDN |
| `azure_tenant_id` | Microsoft Entra ID tenant ID |
| `azure_subscription_id` | Azure subscription ID |
| `azure_app_client_id` | Default Azure App Registration client ID |
| `azure_resource_group_name` | Resource group for the storage account |
| `azure_storage_account_name` | Globally unique storage account name |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `vault_namespace` | `""` | Vault Enterprise namespace |
| `spiffe_mount_path` | `spiffe` | Mount path for the SPIFFE engine |
| `spiffe_role_name` | `azure-wif` | SPIFFE role name |
| `token_ttl` | `10m` | JWT-SVID lifetime |
| `workload_entity_names` | `["a00123-dev", "a00123-staging", "a00123-prod"]` | Workload entity names (format: `<id>-<env>`) |
| `azure_app_registrations` | `{}` | Per-workload App Registration client IDs |
| `azure_location` | `australiaeast` | Azure region |

### Per-Environment App Registrations

By default, all workloads use the `azure_app_client_id` App Registration. To assign dedicated App Registrations per environment:

```hcl
azure_app_registrations = {
  "a00123-staging" = "a3cd4d4c-d150-4d5c-8525-dbc08e4ae55a"
  "a00123-prod"    = "ca6e3b6a-ce95-4100-b886-cb587ef09b79"
}
```

## Entity Name Convention

Entity names follow the format `<workload_id>-<environment>`. Terraform automatically parses these into metadata:

| Entity Name | `workload_id` | `environment` |
|-------------|---------------|---------------|
| `a00123-dev` | `a00123` | `dev` |
| `a00123-staging` | `a00123` | `staging` |
| `a00123-prod` | `a00123` | `prod` |

This produces SPIFFE IDs like:

```
spiffe://vault.example.com/workload/dev/a00123
spiffe://vault.example.com/workload/staging/a00123
spiffe://vault.example.com/workload/prod/a00123
```

## JWT-SVID Structure

The minted JWT-SVID includes a `customer_metadata` block with environment context:

```json
{
  "sub": "spiffe://vault.example.com/workload/dev/a00123",
  "aud": ["api://AzureADTokenExchange"],
  "customer_metadata": {
    "environment": "dev",
    "workload_id": "a00123",
    "azure_client_id": "b4a8dbb8-21ca-4e44-be78-dcd0c03fa8e4"
  },
  "vault": { "entity": { "id": "..." } },
  "iss": "https://vault.example.com/v1/spiffe",
  "exp": 1780044776,
  "iat": 1780044176,
  "jti": "..."
}
```

## Validation

Two scripts are provided to validate the end-to-end WIF flow.

### Bash

```bash
scripts/validate-vault-azure.sh \
  --vault-username a00123-dev \
  --vault-password "$(terraform output -raw workload_passwords | jq -r '."a00123-dev"')" \
  --azure-client-id <client-id> \
  --storage-account <storage-account-name>
```

### Python

```bash
# Setup (one-time)
python3 -m venv .venv && source .venv/bin/activate
pip install -r scripts/requirements.txt

# Run
python scripts/validate-vault-azure.py \
  --vault-username a00123-dev \
  --vault-password "$(terraform output -raw workload_passwords | jq -r '."a00123-dev"')" \
  --azure-client-id <client-id> \
  --storage-account <storage-account-name>
```

Both scripts require `VAULT_ADDR` and `AZURE_TENANT_ID` to be set (via environment variables or flags).

## Outputs

| Output | Description |
|--------|-------------|
| `spiffe_issuer_url` | SPIFFE engine issuer URL |
| `spiffe_discovery_endpoint` | OIDC discovery endpoint |
| `spiffe_jwks_endpoint` | JWKS endpoint for Azure validation |
| `spiffe_mint_endpoint` | JWT-SVID minting endpoint |
| `workload_entity_ids` | Map of entity names to Vault entity IDs |
| `workload_passwords` | Generated userpass passwords (sensitive) |
| `azure_storage_account_name` | Created storage account name |

## Files

```
azure/
├── main.tf              # SPIFFE engine, config, and role
├── entities.tf          # Vault entities, userpass users, aliases
├── azure.tf             # Azure App Registrations, FICs, RBAC
├── storage.tf           # Azure Storage Account + validation container
├── policies.tf          # Vault policy for JWT minting
├── variables.tf         # Input variables
├── outputs.tf           # Terraform outputs
├── versions.tf          # Provider version constraints
└── terraform.tfvars.example
```
