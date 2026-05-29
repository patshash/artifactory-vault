variable "vault_addr" {
  description = "Base URL Terraform uses to manage Vault, for example https://vault.example.com:8200."
  type        = string
}

variable "vault_token" {
  description = "Vault token Terraform will use to configure the SPIFFE engine and entity resources."
  type        = string
  sensitive   = true
}

variable "vault_namespace" {
  description = "Optional Vault Enterprise namespace. Leave empty for the root namespace."
  type        = string
  default     = ""
}

variable "vault_setup_state_path" {
  description = "Path to the local Terraform state file for the vault-setup stack."
  type        = string
  default     = "../vault-setup/terraform.tfstate"
}

variable "spiffe_trust_domain" {
  description = "SPIFFE trust domain — typically the Vault FQDN (e.g. vault.example.com)."
  type        = string
}

variable "spiffe_mount_path" {
  description = "Path to mount the SPIFFE secrets engine in Vault."
  type        = string
  default     = "spiffe"
}

variable "spiffe_role_name" {
  description = "Name of the SPIFFE role used for Azure WIF JWT-SVID minting."
  type        = string
  default     = "azure-wif"
}

variable "workload_entity_names" {
  description = "List of Vault entity names to create. Each maps to a dedicated Azure Service Principal."
  type        = list(string)
  default     = ["a00123-dev", "a00123-staging", "a00123-prod"]
}

variable "token_ttl" {
  description = "TTL for JWT-SVIDs issued by the SPIFFE role."
  type        = string
  default     = "10m"
}

variable "validation_password_length" {
  description = "Length of the generated Vault password for workload users."
  type        = number
  default     = 24
}

variable "azure_tenant_id" {
  description = "Microsoft Entra ID (Azure AD) tenant ID."
  type        = string
}

variable "azure_subscription_id" {
  description = "Azure subscription ID for RBAC role assignments."
  type        = string
}

variable "azure_app_client_id" {
  description = "Application (client) ID of the existing Azure App Registration (dev workload)."
  type        = string
}

variable "azure_app_registrations" {
  description = "Map of workload entity name to Azure App Registration client ID. Used to create per-workload federated identity credentials and RBAC."
  type        = map(string)
  default     = {}
}

variable "azure_resource_group_name" {
  description = "Name of the Azure resource group for the storage account."
  type        = string
}

variable "azure_location" {
  description = "Azure region for the storage account (e.g. australiaeast)."
  type        = string
  default     = "australiaeast"
}

variable "azure_storage_account_name" {
  description = "Name for the Azure Storage Account (must be globally unique, 3-24 lowercase alphanumeric)."
  type        = string
}
