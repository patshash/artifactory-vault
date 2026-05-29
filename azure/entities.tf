# --- Workload name parsing ---
# Entity names like "a00123-dev" are split into workload_id ("a00123") and environment ("dev")

locals {
  workload_parsed = { for name in var.workload_entity_names :
    name => {
      env             = element(split("-", name), length(split("-", name)) - 1)
      workload_id     = join("-", slice(split("-", name), 0, length(split("-", name)) - 1))
      azure_client_id = lookup(var.azure_app_registrations, name, var.azure_app_client_id)
    }
  }
}

# --- Vault Entities (one per workload) ---

resource "vault_identity_entity" "workloads" {
  for_each = toset(var.workload_entity_names)

  name = each.value
  metadata = {
    azure_app_display_name = "vault-spiffe-${each.value}"
    azure_client_id        = local.workload_parsed[each.value].azure_client_id
    purpose                = "Azure WIF workload"
    environment            = local.workload_parsed[each.value].env
    workload_id            = local.workload_parsed[each.value].workload_id
  }
}

# --- Userpass accounts for each workload ---

resource "random_password" "workload_passwords" {
  for_each = toset(var.workload_entity_names)

  length  = var.validation_password_length
  special = false
}

resource "vault_generic_endpoint" "workload_users" {
  for_each = toset(var.workload_entity_names)

  path = "auth/userpass/users/${each.value}"
  data_json = jsonencode({
    password = random_password.workload_passwords[each.value].result
    policies = join(",", ["default", vault_policy.azure_spiffe_user.name])
  })
  ignore_absent_fields = true

  depends_on = [vault_policy.azure_spiffe_user]
}

# --- Entity aliases (link userpass users to entities) ---

resource "vault_identity_entity_alias" "workloads" {
  for_each = toset(var.workload_entity_names)

  name           = each.value
  mount_accessor = local.userpass_auth_mount_accessor
  canonical_id   = vault_identity_entity.workloads[each.value].id
}
