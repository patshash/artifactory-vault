provider "platform" {
  url          = var.jfrog_url
  access_token = var.jfrog_access_token
}

data "terraform_remote_state" "vault_setup" {
  backend = "local"

  config = {
    path = var.vault_setup_state_path
  }
}

locals {
  vault_identity_token_issuer   = data.terraform_remote_state.vault_setup.outputs.vault_identity_token_issuer
  vault_identity_token_audience = data.terraform_remote_state.vault_setup.outputs.vault_identity_token_audience
  jfrog_url_base                = trimsuffix(var.jfrog_url, "/")
  validation_username           = var.azp_claim_match
}

resource "platform_oidc_configuration" "vault" {
  name          = var.oidc_configuration_name
  description   = "vault workload identity"
  issuer_url    = local.vault_identity_token_issuer
  provider_type = "generic"
  audience      = local.vault_identity_token_audience
}

resource "platform_oidc_identity_mapping" "vault_azp_username" {
  name          = var.identity_mapping_name
  description   = "Matches Vault identity tokens by azp and maps azp to the JFrog username."
  provider_name = platform_oidc_configuration.vault.name
  priority      = var.identity_mapping_priority

  claims_json = jsonencode({
    azp = var.azp_claim_match
  })

  token_spec = {
    username_pattern = "{{azp}}"
    scope            = var.jfrog_token_scope
    audience         = var.jfrog_token_audience
    expires_in       = var.jfrog_token_ttl_seconds
  }
}

resource "null_resource" "validation_user" {
  triggers = {
    username = local.validation_username
    email    = var.validation_user_email
    url      = local.jfrog_url_base
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      JFROG_URL_BASE     = local.jfrog_url_base
      JFROG_ACCESS_TOKEN = var.jfrog_access_token
      VALIDATION_USER    = local.validation_username
      VALIDATION_EMAIL   = var.validation_user_email
    }
    command = <<-EOT
      set -euo pipefail

      tmp_response="$$(mktemp)"
      cleanup() {
        rm -f "$${tmp_response}"
      }
      trap cleanup EXIT

      payload="$(
        python3 - <<'PY'
import json
import os

print(json.dumps({
    "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
    "userName": os.environ["VALIDATION_USER"],
    "active": True,
    "emails": [{"value": os.environ["VALIDATION_EMAIL"], "primary": True}],
}))
PY
      )"

      user_url="$${JFROG_URL_BASE}/access/api/v1/scim/v2/Users/$${VALIDATION_USER}"
      status="$(
        curl --silent --show-error \
          --output "$${tmp_response}" \
          --write-out '%%{http_code}' \
          --header "Authorization: Bearer $${JFROG_ACCESS_TOKEN}" \
          --header "Accept: application/json" \
          "$${user_url}" || true
      )"

      case "$${status}" in
        200)
          method="PUT"
          url="$${user_url}"
          ;;
        404)
          method="POST"
          url="$${JFROG_URL_BASE}/access/api/v1/scim/v2/Users"
          ;;
        *)
          cat "$${tmp_response}" >&2
          printf '\n' >&2
          echo "unexpected SCIM lookup status: $${status}" >&2
          exit 1
          ;;
      esac

      write_status="$(
        curl --silent --show-error \
          --output "$${tmp_response}" \
          --write-out '%%{http_code}' \
          --request "$${method}" \
          --header "Authorization: Bearer $${JFROG_ACCESS_TOKEN}" \
          --header "Accept: application/json" \
          --header "Content-Type: application/json" \
          --data "$${payload}" \
          "$${url}"
      )"

      case "$${write_status}" in
        200|201)
          ;;
        *)
          cat "$${tmp_response}" >&2
          printf '\n' >&2
          echo "unable to ensure validation user, status: $${write_status}" >&2
          exit 1
          ;;
      esac
    EOT
  }
}
