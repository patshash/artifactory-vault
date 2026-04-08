#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/validate-vault-jfrog.sh [options]

Requests a Vault identity token, exchanges it for a JFrog access token by using
JFrog CLI via npx, and then runs a final ping against JFrog.

Inputs can be provided as flags or environment variables.

Required:
  --vault-addr / VAULT_ADDR
  --jfrog-url / JFROG_URL

Authentication (choose one):
  --vault-token / VAULT_TOKEN
  --vault-username / VAULT_USERNAME plus --vault-password / VAULT_PASSWORD

Optional:
  --vault-namespace / VAULT_NAMESPACE
  --vault-auth-path / VAULT_AUTH_PATH              Default: userpass
  --vault-role / VAULT_IDENTITY_ROLE               Default: jfrog-token-role
  --jfrog-provider / JFROG_OIDC_PROVIDER           Default: vault
  --jfrog-provider-type / JFROG_OIDC_PROVIDER_TYPE Default: GenericOidc
  --jfrog-audience / JFROG_OIDC_AUDIENCE
  --project / JFROG_PROJECT
  --application-key / JFROG_APPLICATION_KEY
  --repository / JFROG_REPOSITORY
  --help
EOF
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

show_command() {
  local first=1

  printf '    Command:\n'
  for arg in "$@"; do
    if [[ "${first}" -eq 1 ]]; then
      printf '      %q' "$arg"
      first=0
    else
      printf ' \\\n        %q' "$arg"
    fi
  done
  printf '\n'
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

curl_request() {
  local response_file="${tmp_dir}/curl-response.json"
  local status

  status="$(
    curl --silent --show-error \
      --output "${response_file}" \
      --write-out '%{http_code}' \
      "$@"
  )"

  if [[ ! "${status}" =~ ^2 ]]; then
    if [[ -s "${response_file}" ]]; then
      cat "${response_file}" >&2
      printf '\n' >&2
    fi
    fail "request failed with HTTP ${status}"
  fi

  cat "${response_file}"
}

prompt_value() {
  local var_name="$1"
  local prompt_text="$2"
  if [[ -z "${!var_name:-}" ]]; then
    [[ -t 0 ]] || fail "missing required input: $var_name"
    read -r -p "$prompt_text: " "$var_name"
  fi
}

prompt_secret() {
  local var_name="$1"
  local prompt_text="$2"
  if [[ -z "${!var_name:-}" ]]; then
    [[ -t 0 ]] || fail "missing required secret input: $var_name"
    read -r -s -p "$prompt_text: " "$var_name"
    printf '\n'
  fi
}

url_encode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

json_get() {
  local expression="$1"
  python3 -c '
import json
import sys

expr = sys.argv[1]
data = json.load(sys.stdin)
value = data
for part in expr.split("."):
    value = value[part]
if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
' "$expression"
}

VAULT_AUTH_PATH="${VAULT_AUTH_PATH:-userpass}"
VAULT_IDENTITY_ROLE="${VAULT_IDENTITY_ROLE:-jfrog-token-role}"
JFROG_OIDC_PROVIDER="${JFROG_OIDC_PROVIDER:-vault}"
JFROG_OIDC_PROVIDER_TYPE="${JFROG_OIDC_PROVIDER_TYPE:-GenericOidc}"
JFROG_CLI_PACKAGE="${JFROG_CLI_PACKAGE:-jfrog-cli-v2-jf}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault-addr)
      VAULT_ADDR="$2"
      shift 2
      ;;
    --vault-namespace)
      VAULT_NAMESPACE="$2"
      shift 2
      ;;
    --vault-auth-path)
      VAULT_AUTH_PATH="$2"
      shift 2
      ;;
    --vault-role)
      VAULT_IDENTITY_ROLE="$2"
      shift 2
      ;;
    --vault-token)
      VAULT_TOKEN="$2"
      shift 2
      ;;
    --vault-username)
      VAULT_USERNAME="$2"
      shift 2
      ;;
    --vault-password)
      VAULT_PASSWORD="$2"
      shift 2
      ;;
    --jfrog-url)
      JFROG_URL="$2"
      shift 2
      ;;
    --jfrog-provider)
      JFROG_OIDC_PROVIDER="$2"
      shift 2
      ;;
    --jfrog-provider-type)
      JFROG_OIDC_PROVIDER_TYPE="$2"
      shift 2
      ;;
    --jfrog-audience)
      JFROG_OIDC_AUDIENCE="$2"
      shift 2
      ;;
    --project)
      JFROG_PROJECT="$2"
      shift 2
      ;;
    --application-key)
      JFROG_APPLICATION_KEY="$2"
      shift 2
      ;;
    --repository)
      JFROG_REPOSITORY="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

case "${JFROG_OIDC_PROVIDER_TYPE,,}" in
  generic)
    JFROG_OIDC_PROVIDER_TYPE="GenericOidc"
    ;;
  genericoidc)
    JFROG_OIDC_PROVIDER_TYPE="GenericOidc"
    ;;
  azure)
    JFROG_OIDC_PROVIDER_TYPE="Azure"
    ;;
  github)
    JFROG_OIDC_PROVIDER_TYPE="GitHub"
    ;;
esac

require_command curl
require_command npx
require_command python3

[[ -n "${VAULT_ADDR:-}" ]] || fail "VAULT_ADDR or --vault-addr is required"
[[ -n "${JFROG_URL:-}" ]] || fail "JFROG_URL or --jfrog-url is required"

info "Starting validation."
info "This script will authenticate to Vault, request an identity token, exchange it for a JFrog access token, and run a final JFrog ping."

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  info "Step 1/4: Authenticate to Vault with username and password."
  prompt_value VAULT_USERNAME "Vault username"
  prompt_secret VAULT_PASSWORD "Vault password"
else
  info "Step 1/4: Reuse the provided Vault token."
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/validate-vault-jfrog.XXXXXX")"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

export JFROG_CLI_HOME_DIR="${tmp_dir}/jfrog-cli-home"
mkdir -p "${JFROG_CLI_HOME_DIR}"

vault_headers=(
  --header "Content-Type: application/json"
)
if [[ -n "${VAULT_NAMESPACE:-}" ]]; then
  vault_headers+=(--header "X-Vault-Namespace: ${VAULT_NAMESPACE}")
fi

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  encoded_username="$(url_encode "${VAULT_USERNAME}")"
  login_payload="$(
    VAULT_PASSWORD="${VAULT_PASSWORD}" python3 - <<'PY'
import json
import os

print(json.dumps({"password": os.environ["VAULT_PASSWORD"]}))
PY
  )"

  show_command \
    curl \
    --header "Content-Type: application/json" \
    ${VAULT_NAMESPACE:+--header "X-Vault-Namespace: ${VAULT_NAMESPACE}"} \
    --request POST \
    --data '{"password":"[REDACTED]"}' \
    "${VAULT_ADDR%/}/v1/auth/${VAULT_AUTH_PATH#/}/login/${encoded_username}"

  login_response="$(
    curl_request \
      "${vault_headers[@]}" \
      --request POST \
      --data "${login_payload}" \
      "${VAULT_ADDR%/}/v1/auth/${VAULT_AUTH_PATH#/}/login/${encoded_username}"
  )"
  VAULT_TOKEN="$(printf '%s' "${login_response}" | json_get 'auth.client_token')"
  info "Vault login succeeded."
fi

vault_headers+=(--header "X-Vault-Token: ${VAULT_TOKEN}")

info "Step 2/4: Request a Vault identity token from role '${VAULT_IDENTITY_ROLE}'."
show_command \
  curl \
  --header "Content-Type: application/json" \
  ${VAULT_NAMESPACE:+--header "X-Vault-Namespace: ${VAULT_NAMESPACE}"} \
  --header "X-Vault-Token: [REDACTED]" \
  "${VAULT_ADDR%/}/v1/identity/oidc/token/$(url_encode "${VAULT_IDENTITY_ROLE}")"

identity_response="$(
  curl_request \
    "${vault_headers[@]}" \
    "${VAULT_ADDR%/}/v1/identity/oidc/token/$(url_encode "${VAULT_IDENTITY_ROLE}")"
)"
vault_identity_token="$(printf '%s' "${identity_response}" | json_get 'data.token')"

info "Vault identity token acquired."
printf '    Vault identity token: %s\n' "${vault_identity_token}"
info "Step 3/4: Exchange the Vault identity token for a JFrog access token with JFrog CLI."

jfrog_cmd=(
  env
  CI=true
  npx -y "${JFROG_CLI_PACKAGE}"
  eot
  "${JFROG_OIDC_PROVIDER}"
  "${vault_identity_token}"
  --url "${JFROG_URL}"
  --oidc-provider-type "${JFROG_OIDC_PROVIDER_TYPE}"
)

if [[ -n "${JFROG_OIDC_AUDIENCE:-}" ]]; then
  jfrog_cmd+=(--oidc-audience "${JFROG_OIDC_AUDIENCE}")
fi
if [[ -n "${JFROG_PROJECT:-}" ]]; then
  jfrog_cmd+=(--project "${JFROG_PROJECT}")
fi
if [[ -n "${JFROG_APPLICATION_KEY:-}" ]]; then
  jfrog_cmd+=(--application-key "${JFROG_APPLICATION_KEY}")
fi
if [[ -n "${JFROG_REPOSITORY:-}" ]]; then
  jfrog_cmd+=(--repository "${JFROG_REPOSITORY}")
fi

show_command \
  env CI=true \
  npx -y "${JFROG_CLI_PACKAGE}" \
  eot "${JFROG_OIDC_PROVIDER}" "[REDACTED]" \
  --url "${JFROG_URL}" \
  --oidc-provider-type "${JFROG_OIDC_PROVIDER_TYPE}" \
  ${JFROG_OIDC_AUDIENCE:+--oidc-audience "${JFROG_OIDC_AUDIENCE}"} \
  ${JFROG_PROJECT:+--project "${JFROG_PROJECT}"} \
  ${JFROG_APPLICATION_KEY:+--application-key "${JFROG_APPLICATION_KEY}"} \
  ${JFROG_REPOSITORY:+--repository "${JFROG_REPOSITORY}"}

jfrog_exchange_output="$("${jfrog_cmd[@]}")"
printf '%s\n' "${jfrog_exchange_output}"

jfrog_access_token="$(
  printf '%s\n' "${jfrog_exchange_output}" \
    | awk 'NF { line = $0 } END { gsub(/\r/, "", line); print line }'
)"
[[ -n "${jfrog_access_token}" ]] || fail "JFrog CLI did not return an access token"

info "JFrog access token acquired."
info "Step 4/4: Ping the JFrog server."

show_command \
  curl \
  --header "Authorization: Bearer [REDACTED]" \
  "${JFROG_URL%/}/router/api/v1/system/ping"

jfrog_ping_response="$(
  curl_request \
    --header "Authorization: Bearer ${jfrog_access_token}" \
    "${JFROG_URL%/}/router/api/v1/system/ping"
)"

info "JFrog ping response: ${jfrog_ping_response}"
info "Validation complete."
