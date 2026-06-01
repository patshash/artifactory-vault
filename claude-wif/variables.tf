variable "vault_addr" {
  description = "Base URL Terraform uses to manage Vault, for example https://vault.example.com:8200."
  type        = string
}

variable "vault_token" {
  description = "Vault token Terraform will use to configure the SPIFFE secrets engine resources."
  type        = string
  sensitive   = true
}

variable "vault_namespace" {
  description = "Optional Vault Enterprise namespace. Leave empty for the root namespace."
  type        = string
  default     = ""
}

variable "vault_setup_state_path" {
  description = "Path to the local Terraform state file for the vault-setup stack (provides userpass auth mount accessor)."
  type        = string
  default     = "../vault-setup/terraform.tfstate"
}

variable "spiffe_mount_path" {
  description = "Path where the SPIFFE secrets engine is mounted in Vault."
  type        = string
  default     = "spiffe"
}

variable "trust_domain" {
  description = "SPIFFE trust domain for JWT-SVIDs issued by this engine (e.g. vault.example.com)."
  type        = string
}

variable "jwt_issuer_base_url" {
  description = "Base URL for the JWT issuer claim (iss). Must be publicly reachable over HTTPS. Defaults to vault_addr when empty."
  type        = string
  default     = ""
}

variable "jwt_signing_algorithm" {
  description = "Signing algorithm for SPIFFE JWT-SVIDs."
  type        = string
  default     = "RS256"

  validation {
    condition     = contains(["RS256", "RS384", "RS512", "ES256", "ES384", "ES512"], var.jwt_signing_algorithm)
    error_message = "jwt_signing_algorithm must be one of RS256, RS384, RS512, ES256, ES384, ES512."
  }
}

variable "key_lifetime" {
  description = "How often the SPIFFE engine rotates its signing key (Vault duration string, e.g. \"24h\")."
  type        = string
  default     = "24h"
}

variable "role_name" {
  description = "Name of the SPIFFE role used when minting JWT-SVIDs for Claude."
  type        = string
  default     = "claude-token-role"
}

variable "application_audience" {
  description = "Audience passed to the mintjwt endpoint and placed in the aud claim for Anthropic."
  type        = string
  default     = "https://api.anthropic.com"
}

variable "token_ttl" {
  description = "TTL for JWT-SVIDs issued from the role (Vault duration string, e.g. \"1h\"). Maximum 24h per Anthropic."
  type        = string
  default     = "1h"
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

variable "claude_workspace_name" {
  description = "Value for the claude_workspace metadata on the validation user's Vault entity. Used by Anthropic federation rules for workspace routing."
  type        = string
  default     = "wif-workspace"
}
