# Artifactory + Vault OIDC Token Exchange Sandpit

This repository provisions a small AWS sandpit and then configures Vault and JFrog so JFrog can trust Vault-issued identity tokens.

## Repository layout

| Path | Purpose |
| --- | --- |
| `.` | AWS infrastructure for the demo environment |
| `vault-setup/` | Vault identity token issuer, signing key, and OIDC role configuration |
| `vault-plugin-artifactory/` | Standalone installer for the JFrog Artifactory Vault secrets plugin |
| `jfrog_setup/` | JFrog OIDC integration and identity mapping for Vault-issued tokens |
| `claude-wif/` | Anthropic Claude WIF integration for Vault-issued identity tokens |
| `azure/` | Azure Workload Identity Federation using Vault SPIFFE JWT-SVIDs |
| `scripts/` | Helper scripts for end-to-end validation and operator workflows |
| `templates/` | User-data templates used to bootstrap the EC2 instances |

## What the stacks do

### `Root Infrastructure stack`

The root Terraform configuration deploys:

- a dedicated VPC in `ap-southeast-2`
- two public subnets
- a single-node Vault instance on EC2
- a single JFrog server instance on EC2
- a shared internet-facing Application Load Balancer
- ACM certificates and Route53 records for the Vault and Artifactory hostnames

Both service hostnames are exposed over public HTTPS through the shared ALB. SSH remains restricted by `operator_cidr`.

### `JFrog Platform Installation`

The root stack provisions the server, networking, DNS, and HTTPS entrypoint needed for JFrog, but it does **not** complete the licensed JFrog Platform installation for you. Acquiring a license key and completing the JFrog Platform setup flow on the provisioned server are outside the scope of this repository.

Use the official installation guidance for that step: <https://jfrog.com/start-free/install/>
  
This environment requires **JFrog Platform**. It is not expected to work with **Artifactory Open Source**, because the later Terraform and Vault integration in this repo depend on JFrog Platform capabilities and the `jfrog/platform` provider.

### `vault-setup/`

The Vault stack configures the identity token issuer used for JFrog federation. It creates:

- the OIDC signing key
- the `jfrog-token-role` role
- the issuer and token endpoint outputs used by the JFrog stack

The issued Vault identity tokens are shaped for this integration:

- `iss`: `https://vault.<zone>/v1/identity/oidc`
- `aud`: the Artifactory hostname
- `azp`: the Vault entity alias name from the configured auth mount accessor

### `vault-plugin-artifactory/` **OPTIONAL**

The plugin stack is optional and installs and configures the official JFrog Artifactory Vault secrets plugin. It:

- connects to the existing Vault EC2 host over SSH
- ensures `plugin_directory` is configured in `vault.hcl`
- downloads the latest plugin release for the Vault host architecture
- verifies the downloaded binary against the published release checksums
- registers the plugin in the Vault plugin catalog
- mounts the plugin and writes the `config/admin` connection settings

### `jfrog_setup/`

The JFrog stack uses the `jfrog/platform` provider to configure:

- a generic OIDC provider named `vault`
- an identity mapping that matches on the Vault token `azp` claim
- JFrog access tokens whose `username` is derived from `{{azp}}`
- an optional test user for validation

By default it reads `../vault-setup/terraform.tfstate` to discover the live Vault issuer and audience. This stack assumes a working JFrog Platform installation and is not compatible with Artifactory Open Source.

### `claude-wif/`

The Claude WIF stack configures Vault Workload Identity Federation for the Anthropic Claude API. It creates:

- a new OIDC role (`claude-token-role`) with audience `https://api.anthropic.com`
- a Vault policy and validation user for testing
- optionally provisions Anthropic-side resources (service account, federation issuer, federation rule) via the Admin API

The pattern is the same as the JFrog integration: Vault is the OIDC identity provider, Anthropic is the relying party. A workload authenticates to Vault, receives a signed JWT, and exchanges it with Anthropic for a short-lived Claude API access token — no static API keys required.

By default it reads `../vault-setup/terraform.tfstate` to discover the signing key name, userpass mount accessor, and OIDC issuer URL.

### `azure/`

The Azure WIF stack configures Workload Identity Federation between Vault and Microsoft Azure using the **SPIFFE secrets engine**. Unlike the JFrog and Claude integrations (which use Vault's identity OIDC roles), this stack uses Vault's dedicated SPIFFE engine to mint JWT-SVIDs with structured SPIFFE ID subjects.

It creates:

- a SPIFFE secrets engine mount with trust domain configuration
- a SPIFFE role that mints JWT-SVIDs with custom claims (`sub`, `customer_metadata`)
- Vault entities with auto-parsed metadata (workload ID, environment, Azure client ID)
- userpass accounts and entity aliases for each workload
- Azure Federated Identity Credentials on per-environment App Registrations
- Azure Storage Account with RBAC assignments for validation

Entity names follow the convention `<workload_id>-<environment>` (e.g., `a00123-dev`, `a00123-prod`), producing SPIFFE IDs like `spiffe://vault.example.com/workload/dev/a00123`.

Each environment can have its own Azure App Registration for isolation, or share a single registration. The JWT-SVID includes a `customer_metadata` block with `environment`, `workload_id`, and `azure_client_id` for downstream consumers.

By default it reads `../vault-setup/terraform.tfstate` for the userpass auth mount accessor.

## Sensitive files

Variable examples are provided and need to be updated:

- `terraform.tfvars.example`
- `vault-setup/terraform.tfvars.example`
- `vault-plugin-artifactory/terraform.tfvars.example`
- `jfrog_setup/terraform.tfvars.example`
- `claude-wif/terraform.tfvars.example`
- `azure/terraform.tfvars.example`

## Prerequisites

- Terraform `>= 1.5`
- AWS credentials with permission to manage VPC, EC2, IAM, KMS, Route53, ACM, and ELBv2
- access to the Route53 hosted zone you will set in `terraform.tfvars`
- the EC2 key pair you will set in `terraform.tfvars`
- a JFrog admin access token for the Vault plugin stack
- a JFrog admin access token for the JFrog setup stack
- JFrog Platform License Key (Trial)

## Apply order

Apply the stacks in this order.

### 1. Deploy the AWS infrastructure

Create a local tfvars file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Populate at least:

- `route53_zone_name`
- `ssh_key_name`

Then run:

```bash
terraform init
terraform plan
terraform apply 
```

Important inputs:

- `route53_zone_name` and `ssh_key_name`: required user-specific infrastructure values with no tracked defaults
- `operator_cidr`: SSH ingress restriction; leave unset to auto-detect your current public IP
- `vault_dns_label` and `artifactory_dns_label`: labels inside the Route53 zone
- `instance_architecture`: defaults to `amd64`
- `vault_instance_type` and `artifactory_instance_type`: optional size overrides

### 2. Install and Initialize JFrog Artifactory

You will need a license key before progessing further with this. SSH to the Artifactory node with the SSH key configured earlier. In the root directory the latest (Apr 2026) version of JFrog Platform installer has been downloaded: `/jfrog-rpm-installer.tar.gz`.

Complete the instruction steps:
 - `tar xvzf /jfrog-rpm-installer.tar.gz`
 - `cd jfrog-platform-trial-prox-<version>-rpm/ ; ./install.sh`
 - `systemctl start artifactory.service`
 - Web UI <jfrog URL> to complete setup and enter license key.
 - Change Admin password and generate an Access Key.

### 3. Initialize Vault

Vault is auto-unsealed with AWS KMS, but it still needs a one-time initialization step:

```bash
ssh ubuntu@$(terraform output -raw vault_public_ip) \
  'sudo VAULT_ADDR=http://127.0.0.1:8200 vault operator init'
```

Store the output somewhere safe.

### 4. Configure Vault identity tokens

Create a local tfvars file:

```bash
cp vault-setup/terraform.tfvars.example vault-setup/terraform.tfvars
```

Populate at least:

- `vault_addr`
- `vault_token`
- `oidc_issuer_base_url`

Optional:

- `userpass_auth_path` if you want a non-default auth path; otherwise this stack manages `userpass` itself and derives the mount accessor automatically

If the target Vault already has a `userpass` auth mount enabled outside Terraform, import it once before the first apply:

```bash
terraform -chdir=vault-setup import vault_auth_backend.userpass userpass
```

Then run:

```bash
terraform -chdir=vault-setup init
terraform -chdir=vault-setup plan -out vault-setup.tfplan
terraform -chdir=vault-setup apply vault-setup.tfplan
```

After apply, retrieve the validation-script credentials with:

```bash
terraform -chdir=vault-setup output validation_vault_username
terraform -chdir=vault-setup output -raw validation_vault_password
```

The password is generated by Terraform and stored in the local `vault-setup` state file.

### 5. Configure JFrog OIDC

Create a local tfvars file:

```bash
cp jfrog_setup/terraform.tfvars.example jfrog_setup/terraform.tfvars
```

Populate at least:

- `jfrog_url`
- `jfrog_access_token`

The JFrog stack configures the OIDC provider, the `azp`-based identity mapping, and ensures the validation user exists in JFrog through the SCIM API. This avoids the refresh bug in the `platform_scim_user` resource when a user is deleted outside Terraform.

Then run:

```bash
terraform -chdir=jfrog_setup init
terraform -chdir=jfrog_setup plan -out jfrog-setup.tfplan
terraform -chdir=jfrog_setup apply jfrog-setup.tfplan
```

### 6. Configure Claude WIF

Create a local tfvars file:

```bash
cp claude-wif/terraform.tfvars.example claude-wif/terraform.tfvars
```

Populate at least:

- `vault_addr`
- `vault_token`

Complete the Anthropic Console setup manually first (see [`claude-wif/anthropic-console-setup.md`](claude-wif/anthropic-console-setup.md)).

Then run:

```bash
terraform -chdir=claude-wif init
terraform -chdir=claude-wif plan -out claude-wif.tfplan
terraform -chdir=claude-wif apply claude-wif.tfplan
```

After apply, retrieve the validation-script credentials with:

```bash
terraform -chdir=claude-wif output validation_vault_username
terraform -chdir=claude-wif output -raw validation_vault_password
```

### 7. Configure Azure WIF

Create a local tfvars file:

```bash
cp azure/terraform.tfvars.example azure/terraform.tfvars
```

Populate at least:

- `vault_addr`
- `vault_token`
- `spiffe_trust_domain`
- `azure_tenant_id`
- `azure_subscription_id`
- `azure_app_client_id`
- `azure_resource_group_name`
- `azure_storage_account_name`

Optionally configure per-environment App Registrations in `azure_app_registrations`.

Then run:

```bash
terraform -chdir=azure init
terraform -chdir=azure plan -out azure.tfplan
terraform -chdir=azure apply azure.tfplan
```

After apply, retrieve the workload credentials with:

```bash
terraform -chdir=azure output -json workload_passwords
```

## Validation scripts

### JFrog validation

Use `scripts/validate-vault-jfrog.sh` to validate the end-to-end JFrog flow by:

1. authenticating to Vault
2. requesting an identity token from `identity/oidc/token/<role>`
3. exchanging that token for a JFrog access token with JFrog CLI via `npx -y jfrog-cli-v2-jf eot`
4. pinging the JFrog Platform router endpoint with the exchanged access token

The JFrog Terraform stack does not create the validation user. If your JFrog Platform requires the mapped username to already exist, create a user that matches `azp_claim_match` before running the validation flow.

The script accepts sensitive values as flags or environment variables. To avoid leaking secrets into shell history, prefer environment variables and let the script prompt for the Vault password when needed. It prints each command in a multiline, redacted format before running it, and it prints the Vault identity token returned in step 2 before exchanging it with JFrog.

Treat the printed Vault identity token as sensitive. It is short-lived, but it is still a bearer token and should not be copied into logs or shared channels unless that is intentional for your validation workflow.

Required inputs:

- `VAULT_ADDR` or `--vault-addr`
- `JFROG_URL` or `--jfrog-url`
- either `VAULT_TOKEN` / `--vault-token` or a Vault username/password pair

If you use `VAULT_TOKEN`, it must be a Vault token that is associated with an identity entity. Root tokens and other token-auth tokens without an entity cannot mint identity tokens from `identity/oidc/token/<role>`.

Useful optional inputs:

- `VAULT_NAMESPACE` or `--vault-namespace`
- `VAULT_AUTH_PATH` or `--vault-auth-path` (defaults to `userpass`)
- `VAULT_IDENTITY_ROLE` or `--vault-role` (defaults to `jfrog-token-role`)
- `JFROG_OIDC_PROVIDER` or `--jfrog-provider` (defaults to `vault`)
- `JFROG_OIDC_PROVIDER_TYPE` or `--jfrog-provider-type` (defaults to `GenericOidc`)
- `JFROG_OIDC_AUDIENCE` or `--jfrog-audience`

Example:

```bash
export VAULT_ADDR="https://vault.example.com"
export VAULT_USERNAME="vault-oidc-test-user"
export JFROG_URL="https://artifactory.example.com"

./scripts/validate-vault-jfrog.sh
```

If you prefer to skip the login step and reuse an existing Vault token:

```bash
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="replace-me-with-a-vault-token"
export JFROG_URL="https://artifactory.example.com"

./scripts/validate-vault-jfrog.sh --vault-role jfrog-token-role
```

Requirements for the script:

- `bash`
- `curl`
- `python3`
- `node` / `npx`

### Claude validation

Use `scripts/validate-vault-claude.sh` to validate the end-to-end Claude WIF flow by:

1. authenticating to Vault
2. requesting an identity token from `identity/oidc/token/claude-token-role`
3. exchanging that token with Anthropic via WIF (`jwt-bearer` grant)
4. calling the Claude Messages API with the exchanged access token

Required inputs:

- `VAULT_ADDR` or `--vault-addr`
- `ANTHROPIC_ORGANIZATION_ID` or `--organization-id`
- `ANTHROPIC_SERVICE_ACCOUNT_ID` or `--service-account-id`
- `ANTHROPIC_FEDERATION_RULE_ID` or `--federation-rule-id`
- either `VAULT_TOKEN` / `--vault-token` or a Vault username/password pair

Example:

```bash
export VAULT_ADDR="https://vault.example.com"
export VAULT_USERNAME="vault-claude-test-user"
export ANTHROPIC_ORGANIZATION_ID="org_..."
export ANTHROPIC_SERVICE_ACCOUNT_ID="svac_..."
export ANTHROPIC_FEDERATION_RULE_ID="fdrl_..."
export ANTHROPIC_WORKSPACE_ID="wrkspc_..."  # required when rule spans multiple workspaces

./scripts/validate-vault-claude.sh
```

Requirements for the script:

- `bash`
- `curl`
- `python3`

### Azure validation

Use `scripts/validate-vault-azure.sh` (bash) or `scripts/validate-vault-azure.py` (Python) to validate the end-to-end Azure WIF flow by:

1. authenticating to Vault (userpass)
2. minting a JWT-SVID from the SPIFFE engine
3. exchanging the JWT-SVID with Microsoft Entra ID for an Azure access token
4. calling the Azure Storage API to list containers

Required inputs:

- `VAULT_ADDR` or `--vault-addr`
- `AZURE_TENANT_ID` or `--azure-tenant-id`
- `AZURE_CLIENT_ID` or `--azure-client-id`
- `AZURE_STORAGE_ACCOUNT` or `--storage-account`
- either `VAULT_TOKEN` / `--vault-token` or a Vault username/password pair

Example (bash):

```bash
export VAULT_ADDR="https://vault.example.com"
export AZURE_TENANT_ID="00000000-0000-0000-0000-000000000000"

./scripts/validate-vault-azure.sh \
  --vault-username a00123-dev \
  --azure-client-id <client-id> \
  --storage-account vaultspiffewif
```

Example (Python):

```bash
source .venv/bin/activate  # pip install -r scripts/requirements.txt
python scripts/validate-vault-azure.py \
  --vault-username a00123-dev \
  --azure-client-id <client-id> \
  --storage-account vaultspiffewif
```

Requirements:

- Bash script: `bash`, `curl`, `python3`
- Python script: `requests`, `azure-identity`, `azure-storage-blob` (see `scripts/requirements.txt`)

## End-to-end auth flows

### JFrog

Once all stacks are applied:

1. authenticate to Vault with a userpass user that has an associated entity
2. request a Vault identity token from `identity/oidc/token/jfrog-token-role`
3. exchange that token with JFrog at `/access/api/v1/oidc/token`
4. receive a JFrog access token for the username derived from the Vault token `azp` claim

### Claude

Once the `claude-wif/` stack is applied:

1. authenticate to Vault with a userpass user that has an associated entity
2. request a Vault identity token from `identity/oidc/token/claude-token-role`
3. exchange that token with Anthropic at `https://api.anthropic.com/v1/oauth/token` using the `jwt-bearer` grant type
4. receive a short-lived `sk-ant-oat01-...` access token scoped to the configured service account

### Azure

Once the `azure/` stack is applied:

1. authenticate to Vault with a workload userpass user (e.g., `a00123-dev`)
2. mint a JWT-SVID from `spiffe/role/azure-wif/mintjwt`
3. exchange the JWT-SVID with Microsoft Entra ID at `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token` using `client_credentials` grant with federated credential
4. receive an Azure access token scoped to the App Registration's RBAC permissions


### Install the Artifactory Vault plugin **OPTIONAL**

Create a local tfvars file:

```bash
cp vault-plugin-artifactory/terraform.tfvars.example vault-plugin-artifactory/terraform.tfvars
```

Populate at least:

- `vault_token`
- `artifactory_access_token`
- `vault_ssh_private_key_path`

Then run:

```bash
terraform -chdir=vault-plugin-artifactory init
terraform -chdir=vault-plugin-artifactory plan -out vault-plugin-artifactory.tfplan
terraform -chdir=vault-plugin-artifactory apply vault-plugin-artifactory.tfplan
```

By default this stack reads `../terraform.tfstate` for `vault_url`, `vault_public_ip`, `artifactory_url`, and the Vault instance architecture. You can override those values directly in `terraform.tfvars` if needed.

## Destroy

Destroy in reverse order:

```bash
terraform -chdir=vault-plugin-artifactory destroy
terraform -chdir=azure destroy
terraform -chdir=claude-wif destroy
terraform -chdir=jfrog_setup destroy
terraform -chdir=vault-setup destroy
terraform destroy
```
