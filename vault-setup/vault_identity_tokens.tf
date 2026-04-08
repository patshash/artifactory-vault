terraform {
  required_version = ">= 1.5.0"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "vault" {
  address   = var.vault_addr
  token     = var.vault_token
  namespace = local.namespace_value == "" ? null : local.namespace_value
}

locals {
  namespace_value  = trim(var.vault_namespace, "/")
  namespace_prefix = local.namespace_value == "" ? "" : "/${local.namespace_value}"
  vault_api_base   = "${trimsuffix(var.vault_addr, "/")}/v1${local.namespace_prefix}"
  oidc_issuer_base = trimsuffix(var.oidc_issuer_base_url == "" ? var.vault_addr : var.oidc_issuer_base_url, "/")
  oidc_issuer      = "${local.oidc_issuer_base}/v1${local.namespace_prefix}/identity/oidc"
}

resource "vault_identity_oidc" "identity_tokens" {
  issuer = local.oidc_issuer_base
}

resource "vault_identity_oidc_key" "application" {
  name             = var.oidc_key_name
  algorithm        = var.key_algorithm
  rotation_period  = var.key_rotation_period_seconds
  verification_ttl = var.key_verification_ttl_seconds
}

resource "vault_auth_backend" "userpass" {
  type = "userpass"
  path = var.userpass_auth_path
}

resource "vault_policy" "jfrog_token_user" {
  name   = "jfrog-token-user"
  policy = file("${path.module}/jfrog-token-user-policy.hcl")
}

resource "random_password" "validation_user" {
  length  = var.validation_password_length
  special = false
}

resource "vault_generic_endpoint" "validation_user" {
  path = "auth/${vault_auth_backend.userpass.path}/users/${var.validation_username}"
  data_json = jsonencode({
    password = random_password.validation_user.result
    policies = join(",", ["default", vault_policy.jfrog_token_user.name])
  })
  ignore_absent_fields = true

  depends_on = [vault_policy.jfrog_token_user]
}

resource "vault_identity_oidc_role" "application" {
  name      = var.role_name
  key       = vault_identity_oidc_key.application.name
  template  = <<-EOT
  {
    "azp": {{identity.entity.aliases.${vault_auth_backend.userpass.accessor}.name}},
    "metadata": {{identity.entity.metadata}}
  }
  EOT
  client_id = var.application_audience
  ttl       = var.token_ttl_seconds
}

resource "vault_identity_oidc_key_allowed_client_id" "application" {
  key_name          = vault_identity_oidc_key.application.name
  allowed_client_id = vault_identity_oidc_role.application.client_id
}

output "vault_identity_token_role_name" {
  description = "Vault OIDC role name applications can use with /identity/oidc/token/:role_name."
  value       = vault_identity_oidc_role.application.name
}

output "vault_identity_token_audience" {
  description = "Audience configured for the issued identity tokens."
  value       = vault_identity_oidc_role.application.client_id
}

output "vault_identity_token_endpoint" {
  description = "Endpoint applications call to have Vault issue an identity token for the role."
  value       = "${local.vault_api_base}/identity/oidc/token/${vault_identity_oidc_role.application.name}"
}

output "vault_identity_token_issuer" {
  description = "Issuer advertised in Vault identity tokens and discovery metadata."
  value       = local.oidc_issuer
}

output "userpass_auth_mount_accessor" {
  description = "Accessor for the userpass auth mount managed by this stack and used for the azp claim."
  value       = vault_auth_backend.userpass.accessor
}

output "validation_vault_username" {
  description = "Vault username to use with scripts/validate-vault-jfrog.sh."
  value       = var.validation_username
}

output "validation_vault_password" {
  description = "Generated Vault password to use with scripts/validate-vault-jfrog.sh."
  value       = random_password.validation_user.result
  sensitive   = true
}

output "vault_identity_token_discovery_endpoint" {
  description = "Public discovery document for Vault identity tokens."
  value       = "${local.oidc_issuer}/.well-known/openid-configuration"
}

output "vault_identity_token_jwks_endpoint" {
  description = "Public JWKS endpoint applications can use to validate Vault identity tokens."
  value       = "${local.oidc_issuer}/.well-known/keys"
}
