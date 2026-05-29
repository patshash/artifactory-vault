output "spiffe_issuer_url" {
  description = "SPIFFE engine issuer URL (used in Azure FIC and discovery)."
  value       = local.spiffe_issuer_url
}

output "spiffe_discovery_endpoint" {
  description = "SPIFFE OIDC discovery endpoint."
  value       = "${local.spiffe_issuer_url}/.well-known/openid-configuration"
}

output "spiffe_jwks_endpoint" {
  description = "SPIFFE JWKS endpoint for Azure to validate JWT-SVIDs."
  value       = "${local.spiffe_issuer_url}/.well-known/keys"
}

output "spiffe_mint_endpoint" {
  description = "Endpoint workloads call to mint a JWT-SVID."
  value       = "${local.vault_api_base}/${var.spiffe_mount_path}/role/${var.spiffe_role_name}/mintjwt"
}

output "workload_entity_ids" {
  description = "Map of workload entity name to Vault entity ID."
  value       = { for name, entity in vault_identity_entity.workloads : name => entity.id }
}

output "workload_passwords" {
  description = "Map of workload entity name to generated password."
  value       = { for name, pw in random_password.workload_passwords : name => pw.result }
  sensitive   = true
}

output "azure_app_client_ids" {
  description = "Azure Application (client) ID used for all workloads."
  value       = data.azuread_application.spiffe_demo.client_id
}

output "azure_service_principal_ids" {
  description = "Azure Service Principal object ID used for RBAC."
  value       = data.azuread_service_principal.spiffe_demo.object_id
}

output "azure_tenant_id" {
  description = "Azure tenant ID used for token exchange."
  value       = var.azure_tenant_id
}

output "azure_storage_account_name" {
  description = "Name of the created Azure Storage Account."
  value       = azurerm_storage_account.wif.name
}

output "azure_storage_account_id" {
  description = "Full resource ID of the created Azure Storage Account."
  value       = azurerm_storage_account.wif.id
}
