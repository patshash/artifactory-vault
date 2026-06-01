provider "vault" {
  address   = var.vault_addr
  token     = var.vault_token
  namespace = local.namespace_value == "" ? null : local.namespace_value
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

  spiffe_issuer = "${trimsuffix(var.jwt_issuer_base_url == "" ? var.vault_addr : var.jwt_issuer_base_url, "/")}/v1${local.namespace_prefix}/${var.spiffe_mount_path}"
}

# --- Vault SPIFFE secrets engine for Claude ---

resource "vault_mount" "spiffe" {
  path        = var.spiffe_mount_path
  type        = "spiffe"
  description = "SPIFFE secrets engine for Claude WIF JWT-SVIDs"
}

resource "vault_spiffe_secret_backend_config" "claude" {
  mount                      = vault_mount.spiffe.path
  trust_domain               = var.trust_domain
  jwt_issuer_url             = local.spiffe_issuer
  jwt_signing_algorithm      = var.jwt_signing_algorithm
  key_lifetime               = var.key_lifetime
  jwt_oidc_compatibility_mode = true
}

resource "vault_spiffe_secret_backend_role" "claude" {
  mount = vault_mount.spiffe.path
  name  = var.role_name
  ttl   = var.token_ttl
  template = jsonencode({
    sub             = "spiffe://${var.trust_domain}/claude/{{identity.entity.aliases.${local.userpass_auth_mount_accessor}.name}}"
    azp             = "{{identity.entity.aliases.${local.userpass_auth_mount_accessor}.name}}"
    claude_workspace = "{{identity.entity.metadata.claude_workspace}}"
  })
  use_jti_claim = true
}

# --- Vault policy and validation user ---

resource "vault_policy" "claude_token_user" {
  name   = "claude-token-user"
  policy = file("${path.module}/claude-token-user-policy.hcl")
}

resource "vault_identity_entity" "validation_user" {
  name = var.validation_username
  metadata = {
    claude_workspace = var.claude_workspace_name
  }
}

resource "random_password" "validation_user" {
  length  = var.validation_password_length
  special = false
}

resource "vault_generic_endpoint" "validation_user" {
  path = "auth/userpass/users/${var.validation_username}"
  data_json = jsonencode({
    password = random_password.validation_user.result
    policies = join(",", ["default", vault_policy.claude_token_user.name])
  })
  ignore_absent_fields = true

  depends_on = [vault_policy.claude_token_user]
}

resource "vault_identity_entity_alias" "validation_user" {
  name           = var.validation_username
  mount_accessor = local.userpass_auth_mount_accessor
  canonical_id   = vault_identity_entity.validation_user.id
}

