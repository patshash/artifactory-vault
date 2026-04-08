output "jfrog_oidc_provider_name" {
  description = "JFrog OIDC provider name applications should use during token exchange."
  value       = platform_oidc_configuration.vault.name
}

output "jfrog_oidc_issuer_url" {
  description = "Vault issuer URL registered in JFrog."
  value       = platform_oidc_configuration.vault.issuer_url
}

output "jfrog_oidc_audience" {
  description = "Audience JFrog expects on the incoming Vault identity token."
  value       = platform_oidc_configuration.vault.audience
}

output "jfrog_oidc_identity_mapping_name" {
  description = "JFrog identity mapping name that matches the Vault azp claim."
  value       = platform_oidc_identity_mapping.vault_azp_username.name
}

output "validation_username" {
  description = "Username expected when validating azp-based token exchange and ensured in JFrog by this stack."
  value       = local.validation_username
}
