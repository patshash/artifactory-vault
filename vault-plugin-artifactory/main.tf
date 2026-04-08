data "terraform_remote_state" "root" {
  backend = "local"

  config = {
    path = var.root_state_path
  }
}

data "http" "latest_release" {
  url = "https://api.github.com/repos/jfrog/vault-plugin-secrets-artifactory/releases/latest"

  request_headers = {
    Accept = "application/vnd.github+json"
  }
}

locals {
  namespace_value          = trim(var.vault_namespace, "/")
  root_outputs             = data.terraform_remote_state.root.outputs
  effective_vault_addr     = trimsuffix(var.vault_addr != "" ? var.vault_addr : local.root_outputs.vault_url, "/")
  effective_vault_ssh_host = var.vault_ssh_host != "" ? var.vault_ssh_host : local.root_outputs.vault_public_ip
  effective_artifactory_url = trimsuffix(
    var.artifactory_url != "" ? var.artifactory_url : local.root_outputs.artifactory_url,
    "/",
  )
  effective_plugin_arch       = var.plugin_target_arch != "" ? var.plugin_target_arch : try(local.root_outputs.vault_instance_architecture, "amd64")
  latest_release              = jsondecode(data.http.latest_release.response_body)
  plugin_release_tag          = local.latest_release.tag_name
  plugin_release_version      = trimprefix(local.plugin_release_tag, "v")
  plugin_binary_asset_name    = "artifactory-secrets-plugin_${local.plugin_release_version}_linux_${local.effective_plugin_arch}"
  plugin_checksums_asset_name = "artifactory-secrets-plugin_${local.plugin_release_version}.checksums.txt"
  plugin_download_url = one([
    for asset in local.latest_release.assets : asset.browser_download_url
    if asset.name == local.plugin_binary_asset_name
  ])
  plugin_checksums_download_url = one([
    for asset in local.latest_release.assets : asset.browser_download_url
    if asset.name == local.plugin_checksums_asset_name
  ])
}

data "http" "plugin_checksums" {
  url = local.plugin_checksums_download_url
}

locals {
  plugin_checksum_line = one([
    for line in split("\n", trimspace(data.http.plugin_checksums.response_body)) : trimspace(line)
    if endswith(trimspace(line), local.plugin_binary_asset_name)
  ])
  plugin_sha256 = substr(local.plugin_checksum_line, 0, 64)
  plugin_install_script = templatefile("${path.module}/../templates/vault-artifactory-plugin-install.sh.tftpl", {
    vault_plugin_arch      = local.effective_plugin_arch
    vault_plugin_directory = var.plugin_directory
  })
  artifactory_admin_config = merge(
    {
      url                                 = local.effective_artifactory_url
      access_token                        = var.artifactory_access_token
      bypass_artifactory_tls_verification = var.bypass_artifactory_tls_verification
      use_expiring_tokens                 = var.use_expiring_tokens
      allow_scope_override                = var.allow_scope_override
      revoke_on_delete                    = var.revoke_on_delete
    },
    var.username_template == "" ? {} : {
      username_template = var.username_template
    },
  )
}

provider "vault" {
  address   = local.effective_vault_addr
  token     = var.vault_token
  namespace = local.namespace_value == "" ? null : local.namespace_value
}

resource "null_resource" "install_plugin_binary" {
  triggers = {
    vault_ssh_host    = local.effective_vault_ssh_host
    plugin_directory  = var.plugin_directory
    plugin_arch       = local.effective_plugin_arch
    plugin_release    = local.plugin_release_tag
    plugin_sha256     = local.plugin_sha256
    install_script_id = sha256(local.plugin_install_script)
  }

  connection {
    type        = "ssh"
    host        = local.effective_vault_ssh_host
    user        = var.vault_ssh_user
    private_key = file(var.vault_ssh_private_key_path)
  }

  provisioner "file" {
    content     = local.plugin_install_script
    destination = "/tmp/install-artifactory-plugin.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 700 /tmp/install-artifactory-plugin.sh",
      "sudo /bin/sh -c 'if grep -q \"^plugin_directory =\" /etc/vault.d/vault.hcl; then sed -i \"s#^plugin_directory = .*#plugin_directory = \\\"${var.plugin_directory}\\\"#\" /etc/vault.d/vault.hcl; else sed -i \"/^disable_mlock = true$/a plugin_directory = \\\"${var.plugin_directory}\\\"\" /etc/vault.d/vault.hcl; fi'",
      "sudo /tmp/install-artifactory-plugin.sh",
      "sudo test -x '${var.plugin_directory}/${var.plugin_command}'",
      "sudo systemctl restart vault",
      "for attempt in $(seq 1 30); do if sudo systemctl is-active --quiet vault; then exit 0; fi; sleep 2; done; echo 'vault service did not become active' >&2; exit 1",
      "for attempt in $(seq 1 30); do code=$(curl -s -o /dev/null -w '%%{http_code}' http://127.0.0.1:8200/v1/sys/health || true); case \"$code\" in 200|429|472|473|501|503) exit 0 ;; esac; sleep 2; done; echo 'vault API did not become ready' >&2; exit 1",
    ]
  }
}

resource "vault_plugin" "artifactory" {
  name    = var.plugin_name
  type    = "secret"
  command = var.plugin_command
  sha256  = local.plugin_sha256
  version = local.plugin_release_tag

  depends_on = [null_resource.install_plugin_binary]
}

resource "vault_mount" "artifactory" {
  path           = var.plugin_mount_path
  type           = var.plugin_name
  description    = var.plugin_mount_description
  plugin_version = local.plugin_release_tag

  depends_on = [vault_plugin.artifactory]
}

resource "vault_generic_endpoint" "artifactory_admin_config" {
  path                 = "${vault_mount.artifactory.path}/config/admin"
  data_json            = jsonencode(local.artifactory_admin_config)
  ignore_absent_fields = true

  depends_on = [vault_mount.artifactory]
}

resource "vault_generic_endpoint" "artifactory_admin_rotation" {
  count = var.rotate_admin_token ? 1 : 0

  path         = "${vault_mount.artifactory.path}/config/rotate"
  data_json    = jsonencode({})
  disable_read = true

  depends_on = [vault_generic_endpoint.artifactory_admin_config]
}
