variable "vault_addr" {
  description = "Base URL Terraform uses to manage Vault, for example https://vault.example.com:8200."
  type        = string
}

variable "vault_token" {
  description = "Vault token Terraform will use to configure the OIDC identity resources."
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

variable "role_name" {
  description = "Name of the Vault OIDC role used when requesting identity tokens for Claude."
  type        = string
  default     = "claude-token-role"
}

variable "application_audience" {
  description = "Audience placed in the issued identity token's aud claim for Anthropic."
  type        = string
  default     = "https://api.anthropic.com"
}

variable "token_ttl_seconds" {
  description = "TTL for identity tokens issued from the role, in seconds. Maximum 86400 per Anthropic."
  type        = number
  default     = 3600
}

variable "validation_username" {
  description = "Vault userpass username created for the validation script."
  type        = string
  default     = "vault-claude-test-user"
}

variable "validation_password_length" {
  description = "Length of the generated Vault password for the validation user."
  type        = number
  default     = 24
}
