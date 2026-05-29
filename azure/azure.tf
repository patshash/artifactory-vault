# --- Existing Azure App Registration (dev workload) ---

data "azuread_application" "spiffe_demo" {
  client_id = var.azure_app_client_id
}

data "azuread_service_principal" "spiffe_demo" {
  client_id = var.azure_app_client_id
}

# --- Additional Azure App Registrations (per-workload) ---

data "azuread_application" "workloads" {
  for_each  = var.azure_app_registrations
  client_id = each.value
}

data "azuread_service_principal" "workloads" {
  for_each  = var.azure_app_registrations
  client_id = each.value
}

# --- Federated Identity Credentials ---

# Dev workload (uses the original spiffe-demo app registration)
resource "azuread_application_federated_identity_credential" "workloads" {
  for_each = toset([for name in var.workload_entity_names : name if !contains(keys(var.azure_app_registrations), name)])

  application_id = data.azuread_application.spiffe_demo.id
  display_name   = "vault-spiffe-${each.value}"
  issuer         = local.spiffe_issuer_url
  subject        = "spiffe://${var.spiffe_trust_domain}/workload/${local.workload_parsed[each.value].env}/${local.workload_parsed[each.value].workload_id}"
  audiences      = ["api://AzureADTokenExchange"]
  description    = "Trust Vault SPIFFE JWT-SVID for entity: ${each.value}"
}

# Staging/Prod workloads (each has its own app registration)
resource "azuread_application_federated_identity_credential" "per_app_workloads" {
  for_each = var.azure_app_registrations

  application_id = data.azuread_application.workloads[each.key].id
  display_name   = "vault-spiffe-${each.key}"
  issuer         = local.spiffe_issuer_url
  subject        = "spiffe://${var.spiffe_trust_domain}/workload/${local.workload_parsed[each.key].env}/${local.workload_parsed[each.key].workload_id}"
  audiences      = ["api://AzureADTokenExchange"]
  description    = "Trust Vault SPIFFE JWT-SVID for entity: ${each.key}"
}

# --- RBAC: Storage Blob Data Contributor ---

resource "azurerm_role_assignment" "spiffe_demo" {
  scope                = azurerm_storage_account.wif.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_service_principal.spiffe_demo.object_id
}

resource "azurerm_role_assignment" "per_app_workloads" {
  for_each = var.azure_app_registrations

  scope                = azurerm_storage_account.wif.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_service_principal.workloads[each.key].object_id
}
