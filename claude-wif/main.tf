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

  vault_identity_token_issuer  = data.terraform_remote_state.vault_setup.outputs.vault_identity_token_issuer
  userpass_auth_mount_accessor = data.terraform_remote_state.vault_setup.outputs.userpass_auth_mount_accessor
  oidc_signing_key_name        = data.terraform_remote_state.vault_setup.outputs.vault_identity_oidc_key_name
}

# --- Vault OIDC role for Claude ---

resource "vault_identity_oidc_role" "claude" {
  name      = var.role_name
  key       = local.oidc_signing_key_name
  template  = <<-EOT
  {
    "azp": {{identity.entity.aliases.${local.userpass_auth_mount_accessor}.name}},
    "metadata": {{identity.entity.metadata}}
  }
  EOT
  client_id = var.application_audience
  ttl       = var.token_ttl_seconds
}

resource "vault_identity_oidc_key_allowed_client_id" "claude" {
  key_name          = local.oidc_signing_key_name
  allowed_client_id = vault_identity_oidc_role.claude.client_id
}

# --- Vault policy and validation user ---

resource "vault_policy" "claude_token_user" {
  name   = "claude-token-user"
  policy = file("${path.module}/claude-token-user-policy.hcl")
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

