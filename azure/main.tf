provider "vault" {
  address   = var.vault_addr
  token     = var.vault_token
  namespace = local.namespace_value == "" ? null : local.namespace_value
}

provider "azuread" {
  tenant_id = var.azure_tenant_id
}

provider "azurerm" {
  features {}
  subscription_id                 = var.azure_subscription_id
  tenant_id                       = var.azure_tenant_id
  resource_provider_registrations = "none"
}

data "terraform_remote_state" "vault_setup" {
  backend = "local"

  config = {
    path = var.vault_setup_state_path
  }
}

locals {
  namespace_value  = trim(var.vault_namespace, "/")
  namespace_prefix = local.namespace_value == "" ? "" : "/${local.namespace_value}"
  vault_api_base   = "${trimsuffix(var.vault_addr, "/")}/v1${local.namespace_prefix}"

  userpass_auth_mount_accessor = data.terraform_remote_state.vault_setup.outputs.userpass_auth_mount_accessor

  spiffe_issuer_url = "https://${var.spiffe_trust_domain}/v1/${var.spiffe_mount_path}"
}

# --- SPIFFE Secrets Engine ---

resource "vault_mount" "spiffe" {
  path        = var.spiffe_mount_path
  type        = "spiffe"
  description = "SPIFFE JWT-SVID issuer for Azure Workload Identity Federation"

  default_lease_ttl_seconds = 600
  max_lease_ttl_seconds     = 3600
}

resource "vault_generic_endpoint" "spiffe_config" {
  depends_on = [vault_mount.spiffe]

  path                 = "${vault_mount.spiffe.path}/config"
  disable_read         = false
  disable_delete       = true
  ignore_absent_fields = true

  data_json = jsonencode({
    trust_domain          = var.spiffe_trust_domain
    jwt_issuer_url        = local.spiffe_issuer_url
    jwt_signing_algorithm = "RS256"
    key_lifetime          = "24h"
    bundle_refresh_hint   = "1h"
  })
}

resource "vault_generic_endpoint" "spiffe_role_azure" {
  depends_on = [vault_generic_endpoint.spiffe_config]

  path                 = "${vault_mount.spiffe.path}/role/${var.spiffe_role_name}"
  disable_read         = false
  disable_delete       = false
  ignore_absent_fields = true

  data_json = jsonencode({
    template = jsonencode({
      sub = "spiffe://${var.spiffe_trust_domain}/workload/{{identity.entity.metadata.environment}}/{{identity.entity.metadata.workload_id}}"
      customer_metadata = {
        environment     = "{{identity.entity.metadata.environment}}"
        workload_id     = "{{identity.entity.metadata.workload_id}}"
        azure_client_id = "{{identity.entity.metadata.azure_client_id}}"
      }
    })
    ttl           = var.token_ttl
    use_jti_claim = true
  })
}
