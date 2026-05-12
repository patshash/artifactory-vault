output "vault_identity_token_role_name" {
  description = "Vault OIDC role name for Claude identity tokens."
  value       = vault_identity_oidc_role.claude.name
}

output "vault_identity_token_audience" {
  description = "Audience configured for the issued Claude identity tokens."
  value       = vault_identity_oidc_role.claude.client_id
}

output "vault_identity_token_endpoint" {
  description = "Endpoint applications call to have Vault issue a Claude identity token."
  value       = "${local.vault_api_base}/identity/oidc/token/${vault_identity_oidc_role.claude.name}"
}

output "vault_identity_token_issuer" {
  description = "Issuer advertised in Vault identity tokens and discovery metadata."
  value       = local.vault_identity_token_issuer
}

output "vault_identity_token_discovery_endpoint" {
  description = "Public discovery document for Vault identity tokens."
  value       = "${local.vault_identity_token_issuer}/.well-known/openid-configuration"
}

output "vault_identity_token_jwks_endpoint" {
  description = "Public JWKS endpoint Anthropic uses to validate Vault identity tokens."
  value       = "${local.vault_identity_token_issuer}/.well-known/keys"
}

output "validation_vault_username" {
  description = "Vault username to use with scripts/validate-vault-claude.sh."
  value       = var.validation_username
}

output "validation_vault_password" {
  description = "Generated Vault password to use with scripts/validate-vault-claude.sh."
  value       = random_password.validation_user.result
  sensitive   = true
}
