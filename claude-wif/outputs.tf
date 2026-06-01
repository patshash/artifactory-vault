output "spiffe_mount_path" {
  description = "Path where the SPIFFE secrets engine is mounted."
  value       = vault_mount.spiffe.path
}

output "spiffe_role_name" {
  description = "SPIFFE role name for Claude JWT-SVIDs."
  value       = vault_spiffe_secret_backend_role.claude.name
}

output "spiffe_mintjwt_endpoint" {
  description = "Endpoint applications call to mint a Claude JWT-SVID (POST with audience parameter)."
  value       = "${local.vault_api_base}/${vault_mount.spiffe.path}/role/${vault_spiffe_secret_backend_role.claude.name}/mintjwt"
}

output "spiffe_jwt_audience" {
  description = "Audience value to pass to the mintjwt endpoint for Anthropic."
  value       = var.application_audience
}

output "spiffe_jwt_issuer" {
  description = "Issuer advertised in SPIFFE JWT-SVIDs and discovery metadata."
  value       = local.spiffe_issuer
}

output "spiffe_discovery_endpoint" {
  description = "Public OIDC discovery document for the SPIFFE secrets engine."
  value       = "${local.spiffe_issuer}/.well-known/openid-configuration"
}

output "spiffe_jwks_endpoint" {
  description = "Public JWKS endpoint Anthropic uses to validate SPIFFE JWT-SVIDs."
  value       = "${local.spiffe_issuer}/.well-known/keys"
}

output "spiffe_trust_domain" {
  description = "SPIFFE trust domain configured for this engine."
  value       = var.trust_domain
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
