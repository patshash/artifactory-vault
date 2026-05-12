#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/validate-vault-claude.sh [options]

Requests a Vault identity token, exchanges it for an Anthropic access token
via Workload Identity Federation (jwt-bearer grant), and then calls the Claude
Messages API to verify end-to-end connectivity.

Inputs can be provided as flags or environment variables.

Required:
  --vault-addr / VAULT_ADDR
  --organization-id / ANTHROPIC_ORGANIZATION_ID
  --service-account-id / ANTHROPIC_SERVICE_ACCOUNT_ID
  --federation-rule-id / ANTHROPIC_FEDERATION_RULE_ID

Authentication (choose one):
  --vault-token / VAULT_TOKEN
  --vault-username / VAULT_USERNAME plus --vault-password / VAULT_PASSWORD

Optional:
  --vault-namespace / VAULT_NAMESPACE
  --vault-auth-path / VAULT_AUTH_PATH              Default: userpass
  --vault-role / VAULT_IDENTITY_ROLE               Default: claude-token-role
  --workspace-id / ANTHROPIC_WORKSPACE_ID
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

# --- Defaults ---

VAULT_AUTH_PATH="${VAULT_AUTH_PATH:-userpass}"
VAULT_IDENTITY_ROLE="${VAULT_IDENTITY_ROLE:-claude-token-role}"

# --- Parse arguments ---

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
    --organization-id)
      ANTHROPIC_ORGANIZATION_ID="$2"
      shift 2
      ;;
    --service-account-id)
      ANTHROPIC_SERVICE_ACCOUNT_ID="$2"
      shift 2
      ;;
    --federation-rule-id)
      ANTHROPIC_FEDERATION_RULE_ID="$2"
      shift 2
      ;;
    --workspace-id)
      ANTHROPIC_WORKSPACE_ID="$2"
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

# --- Validate required inputs ---

require_command curl
require_command python3

[[ -n "${VAULT_ADDR:-}" ]] || fail "VAULT_ADDR or --vault-addr is required"
[[ -n "${ANTHROPIC_ORGANIZATION_ID:-}" ]] || fail "ANTHROPIC_ORGANIZATION_ID or --organization-id is required"
[[ -n "${ANTHROPIC_SERVICE_ACCOUNT_ID:-}" ]] || fail "ANTHROPIC_SERVICE_ACCOUNT_ID or --service-account-id is required"
[[ -n "${ANTHROPIC_FEDERATION_RULE_ID:-}" ]] || fail "ANTHROPIC_FEDERATION_RULE_ID or --federation-rule-id is required"

info "Starting validation."
info "This script will authenticate to Vault, request an identity token, exchange it with Anthropic via WIF, and call the Claude Messages API."

# --- Step 1: Authenticate to Vault ---

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  info "Step 1/4: Authenticate to Vault with username and password."
  prompt_value VAULT_USERNAME "Vault username"
  prompt_secret VAULT_PASSWORD "Vault password"
else
  info "Step 1/4: Reuse the provided Vault token."
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/validate-vault-claude.XXXXXX")"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

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

# --- Step 2: Request a Vault identity token ---

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

# --- Step 3: Exchange the Vault identity token with Anthropic ---

info "Step 3/4: Exchange the Vault identity token for an Anthropic access token via WIF."

exchange_payload="$(
  VAULT_JWT="${vault_identity_token}" \
  ORG_ID="${ANTHROPIC_ORGANIZATION_ID}" \
  SA_ID="${ANTHROPIC_SERVICE_ACCOUNT_ID}" \
  RULE_ID="${ANTHROPIC_FEDERATION_RULE_ID}" \
  WORKSPACE_ID="${ANTHROPIC_WORKSPACE_ID:-}" \
  python3 - <<'PY'
import json
import os

payload = {
    "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
    "assertion": os.environ["VAULT_JWT"],
    "federation_rule_id": os.environ["RULE_ID"],
    "organization_id": os.environ["ORG_ID"],
    "service_account_id": os.environ["SA_ID"],
}
ws = os.environ.get("WORKSPACE_ID", "")
if ws:
    payload["workspace_id"] = ws
print(json.dumps(payload))
PY
)"

show_command \
  curl \
  --header "Content-Type: application/json" \
  --request POST \
  --data '{"grant_type":"urn:ietf:params:oauth:grant-type:jwt-bearer","assertion":"[REDACTED]",...}' \
  "https://api.anthropic.com/v1/oauth/token"

exchange_response="$(
  curl_request \
    --header "Content-Type: application/json" \
    --request POST \
    --data "${exchange_payload}" \
    "https://api.anthropic.com/v1/oauth/token"
)"

anthropic_token="$(printf '%s' "${exchange_response}" | json_get 'access_token')"
[[ -n "${anthropic_token}" ]] || fail "Anthropic did not return an access token"

info "Anthropic access token acquired."

# --- Step 4: Call the Claude Messages API ---

info "Step 4/4: Call the Claude Messages API to verify end-to-end connectivity."

show_command \
  curl \
  --header "Authorization: Bearer [REDACTED]" \
  --header "anthropic-version: 2023-06-01" \
  --header "Content-Type: application/json" \
  --request POST \
  --data '{"model":"claude-sonnet-4-20250514","max_tokens":64,"messages":[{"role":"user","content":"Hello from Vault WIF!"}]}' \
  "https://api.anthropic.com/v1/messages"

messages_response="$(
  curl_request \
    --header "Authorization: Bearer ${anthropic_token}" \
    --header "anthropic-version: 2023-06-01" \
    --header "Content-Type: application/json" \
    --request POST \
    --data '{"model":"claude-sonnet-4-20250514","max_tokens":64,"messages":[{"role":"user","content":"Hello from Vault WIF!"}]}' \
    "https://api.anthropic.com/v1/messages"
)"

claude_reply="$(printf '%s' "${messages_response}" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for block in data.get("content", []):
    if block.get("type") == "text":
        print(block["text"])
        break
')"

info "Claude response: ${claude_reply}"
info "Validation complete."
