# --- Azure Resource Group + Storage Account ---

resource "azurerm_resource_group" "wif" {
  name     = var.azure_resource_group_name
  location = var.azure_location
}

resource "azurerm_storage_account" "wif" {
  name                     = var.azure_storage_account_name
  resource_group_name      = azurerm_resource_group.wif.name
  location                 = azurerm_resource_group.wif.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    purpose = "vault-spiffe-wif-validation"
  }
}

resource "azurerm_storage_container" "validation" {
  name                  = "validation"
  storage_account_id    = azurerm_storage_account.wif.id
  container_access_type = "private"
}
