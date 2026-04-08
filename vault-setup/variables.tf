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

variable "oidc_issuer_base_url" {
  description = "Optional base URL Vault should advertise for identity-token discovery. Defaults to vault_addr when empty and should be reachable by relying parties."
  type        = string
  default     = ""
}

variable "oidc_key_name" {
  description = "Name of the Vault OIDC signing key used to sign issued identity tokens."
  type        = string
  default     = "application-identity-signing-key"
}

variable "role_name" {
  description = "Name of the Vault OIDC role applications will use when requesting identity tokens."
  type        = string
  default     = "application-identity-token-role"
}

variable "application_audience" {
  description = "Audience placed in the issued identity token's aud claim. Update this placeholder for your application."
  type        = string
  default     = "replace-me-with-your-application-audience"
}

variable "userpass_auth_path" {
  description = "Path where the userpass auth method should be enabled and managed by this stack."
  type        = string
  default     = "userpass"
}

variable "validation_username" {
  description = "Vault userpass username created for the validation script."
  type        = string
  default     = "vault-oidc-test-user"
}

variable "validation_password_length" {
  description = "Length of the generated Vault password for the validation user."
  type        = number
  default     = 24
}

variable "token_ttl_seconds" {
  description = "TTL for identity tokens issued from the role, in seconds."
  type        = number
  default     = 900
}

variable "key_algorithm" {
  description = "Signing algorithm for the Vault OIDC key."
  type        = string
  default     = "RS256"

  validation {
    condition     = contains(["RS256", "RS384", "RS512", "ES256", "ES384", "ES512", "EdDSA"], var.key_algorithm)
    error_message = "key_algorithm must be one of RS256, RS384, RS512, ES256, ES384, ES512, or EdDSA."
  }
}

variable "key_rotation_period_seconds" {
  description = "How often Vault should rotate the signing key, in seconds."
  type        = number
  default     = 86400
}

variable "key_verification_ttl_seconds" {
  description = "How long Vault should keep old public keys available for verification after rotation, in seconds."
  type        = number
  default     = 604800
}
