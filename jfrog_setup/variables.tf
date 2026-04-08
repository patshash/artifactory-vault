variable "jfrog_url" {
  description = "JFrog Platform base URL."
  type        = string
}

variable "jfrog_access_token" {
  description = "JFrog Platform admin access token used by Terraform."
  type        = string
  sensitive   = true
}

variable "vault_setup_state_path" {
  description = "Path to the local Terraform state file for the vault-setup stack."
  type        = string
  default     = "../vault-setup/terraform.tfstate"
}

variable "oidc_configuration_name" {
  description = "Name of the JFrog OIDC configuration for Vault."
  type        = string
  default     = "vault"
}

variable "identity_mapping_name" {
  description = "Name of the JFrog identity mapping that matches Vault identity tokens."
  type        = string
  default     = "vault-azp-username"
}

variable "identity_mapping_priority" {
  description = "Priority of the JFrog identity mapping. Lower numbers are evaluated first."
  type        = number
  default     = 1
}

variable "azp_claim_match" {
  description = "Exact azp claim value the validation identity mapping should match."
  type        = string
  default     = "vault-oidc-test-user"
}

variable "validation_user_email" {
  description = "Email address used when ensuring the JFrog validation user exists."
  type        = string
  default     = "vault-oidc-test-user@example.com"
}

variable "jfrog_token_scope" {
  description = "Scope issued by JFrog when the Vault azp-based identity mapping matches."
  type        = string
  default     = "applied-permissions/user"
}

variable "jfrog_token_audience" {
  description = "JFrog service audience pattern for issued access tokens."
  type        = string
  default     = "*@*"
}

variable "jfrog_token_ttl_seconds" {
  description = "Lifetime in seconds for the access tokens JFrog issues from this identity mapping."
  type        = number
  default     = 3600
}
