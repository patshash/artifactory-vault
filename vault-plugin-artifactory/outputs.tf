output "vault_artifactory_plugin_release_tag" {
  description = "Latest Artifactory plugin release tag installed and registered by this stack."
  value       = local.plugin_release_tag
}

output "vault_artifactory_plugin_download_url" {
  description = "Release asset URL for the plugin binary that matches the configured Vault host architecture."
  value       = local.plugin_download_url
}

output "vault_artifactory_plugin_mount_path" {
  description = "Vault mount path for the Artifactory secrets engine."
  value       = vault_mount.artifactory.path
}

output "vault_artifactory_plugin_config_path" {
  description = "Vault endpoint used to configure the Artifactory admin connection."
  value       = vault_generic_endpoint.artifactory_admin_config.path
}
