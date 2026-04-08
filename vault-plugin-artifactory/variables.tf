variable "root_state_path" {
  description = "Path to the local Terraform state file for the root infrastructure stack."
  type        = string
  default     = "../terraform.tfstate"
}

variable "vault_addr" {
  description = "Optional Vault URL override. Defaults to the root stack output when empty."
  type        = string
  default     = ""
}

variable "vault_token" {
  description = "Vault token Terraform will use to register and configure the Artifactory plugin."
  type        = string
  sensitive   = true
}

variable "vault_namespace" {
  description = "Optional Vault Enterprise namespace. Leave empty for the root namespace."
  type        = string
  default     = ""
}

variable "vault_ssh_host" {
  description = "Optional SSH host override for the Vault server. Defaults to the root stack public IP when empty."
  type        = string
  default     = ""
}

variable "vault_ssh_user" {
  description = "SSH username for the Vault host."
  type        = string
  default     = "ubuntu"
}

variable "vault_ssh_private_key_path" {
  description = "Absolute path to the SSH private key used to access the Vault host."
  type        = string
}

variable "plugin_target_arch" {
  description = "Optional plugin architecture override. Defaults to the root stack Vault architecture when empty."
  type        = string
  default     = ""

  validation {
    condition     = var.plugin_target_arch == "" || contains(["amd64", "arm64"], var.plugin_target_arch)
    error_message = "plugin_target_arch must be empty, amd64, or arm64."
  }
}

variable "plugin_directory" {
  description = "Directory configured in Vault as plugin_directory and used to store the Artifactory plugin binary."
  type        = string
  default     = "/etc/vault.d/plugins"
}

variable "plugin_name" {
  description = "Vault plugin catalog name for the Artifactory secrets engine."
  type        = string
  default     = "artifactory"
}

variable "plugin_command" {
  description = "Executable name registered in the Vault plugin catalog."
  type        = string
  default     = "artifactory-secrets-plugin"
}

variable "plugin_mount_path" {
  description = "Path where the Artifactory secrets engine should be mounted in Vault."
  type        = string
  default     = "artifactory"
}

variable "plugin_mount_description" {
  description = "Human-friendly description for the mounted Artifactory secrets engine."
  type        = string
  default     = "JFrog Artifactory secrets engine."
}

variable "artifactory_url" {
  description = "Optional Artifactory URL override. Defaults to the root stack output when empty."
  type        = string
  default     = ""
}

variable "artifactory_access_token" {
  description = "JFrog admin access token used by the plugin to mint Artifactory access tokens."
  type        = string
  sensitive   = true
}

variable "username_template" {
  description = "Optional Vault username template for dynamic Artifactory usernames."
  type        = string
  default     = ""
}

variable "bypass_artifactory_tls_verification" {
  description = "Whether the plugin should skip TLS verification when connecting to Artifactory."
  type        = bool
  default     = false
}

variable "use_expiring_tokens" {
  description = "Whether the plugin should request expiring Artifactory tokens when supported."
  type        = bool
  default     = false
}

variable "allow_scope_override" {
  description = "Whether the plugin should allow callers to override scopes when requesting tokens."
  type        = bool
  default     = false
}

variable "revoke_on_delete" {
  description = "Whether Vault should revoke the configured Artifactory admin token when the config is deleted."
  type        = bool
  default     = false
}

variable "rotate_admin_token" {
  description = "Whether Terraform should call the plugin's admin-token rotation endpoint after configuring the plugin."
  type        = bool
  default     = false
}
