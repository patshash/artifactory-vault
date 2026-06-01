#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/validate-vault-azure.sh [options]

Authenticates to Vault, mints a SPIFFE JWT-SVID, exchanges it with Microsoft
Entra ID for an Azure access token, and calls the Azure Storage API to validate
end-to-end Workload Identity Federation.

Inputs can be provided as flags or environment variables.

Required:
  --vault-addr / VAULT_ADDR
  --azure-tenant-id / AZURE_TENANT_ID
  --azure-client-id / AZURE_CLIENT_ID
  --storage-account / AZURE_STORAGE_ACCOUNT

Authentication (choose one):
  --vault-token / VAULT_TOKEN
  --vault-username / VAULT_USERNAME plus --vault-password / VAULT_PASSWORD

Optional:
  --vault-namespace / VAULT_NAMESPACE
  --vault-auth-path / VAULT_AUTH_PATH              Default: userpass
  --spiffe-role / SPIFFE_ROLE                      Default: azure-wif
  --spiffe-mount / SPIFFE_MOUNT                    Default: spiffe
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

decode_jwt() {
  local token="$1"
  local label="${2:-JWT}"
  printf '    %s header:\n' "${label}"
  printf '%s' "${token}" | python3 -c '
import base64, json, sys

token = sys.stdin.read().strip()
parts = token.split(".")

def decode_part(b64):
    padding = 4 - len(b64) % 4
    if padding != 4:
        b64 += "=" * padding
    return json.loads(base64.urlsafe_b64decode(b64))

header = decode_part(parts[0])
print("      " + json.dumps(header, indent=2).replace("\n", "\n      "))
'
  printf '    %s payload:\n' "${label}"
  printf '%s' "${token}" | python3 -c '
import base64, json, sys
from datetime import datetime, timezone

token = sys.stdin.read().strip()
parts = token.split(".")

def decode_part(b64):
    padding = 4 - len(b64) % 4
    if padding != 4:
        b64 += "=" * padding
    return json.loads(base64.urlsafe_b64decode(b64))

payload = decode_part(parts[1])
print("      " + json.dumps(payload, indent=2).replace("\n", "\n      "))

# Show human-readable times for iat/exp/nbf
for field in ("iat", "exp", "nbf"):
    if field in payload:
        ts = datetime.fromtimestamp(payload[field], tz=timezone.utc)
        print(f"      ({field}: {ts.isoformat()})")
'
}

pause() {
  local msg="${1:-Press Enter to continue...}"
  printf '\n    %s' "${msg}"
  read -r
  printf '\n'
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
SPIFFE_ROLE="${SPIFFE_ROLE:-azure-wif}"
SPIFFE_MOUNT="${SPIFFE_MOUNT:-spiffe}"

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
    --spiffe-role)
      SPIFFE_ROLE="$2"
      shift 2
      ;;
    --spiffe-mount)
      SPIFFE_MOUNT="$2"
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
    --azure-tenant-id)
      AZURE_TENANT_ID="$2"
      shift 2
      ;;
    --azure-client-id)
      AZURE_CLIENT_ID="$2"
      shift 2
      ;;
    --storage-account)
      AZURE_STORAGE_ACCOUNT="$2"
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
[[ -n "${AZURE_TENANT_ID:-}" ]] || fail "AZURE_TENANT_ID or --azure-tenant-id is required"
[[ -n "${AZURE_CLIENT_ID:-}" ]] || fail "AZURE_CLIENT_ID or --azure-client-id is required"
[[ -n "${AZURE_STORAGE_ACCOUNT:-}" ]] || fail "AZURE_STORAGE_ACCOUNT or --storage-account is required"

info "Starting Azure WIF validation."
info "This script will authenticate to Vault, mint a SPIFFE JWT-SVID, exchange it with Azure, and call the Storage API."

# --- Step 1: Authenticate to Vault ---

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  info "Step 1/4: Authenticate to Vault with username and password."
  prompt_value VAULT_USERNAME "Vault username"
  prompt_secret VAULT_PASSWORD "Vault password"
else
  info "Step 1/4: Reuse the provided Vault token."
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/validate-vault-azure.XXXXXX")"
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
  printf '    Vault token: %s...%s\n' "${VAULT_TOKEN:0:10}" "${VAULT_TOKEN: -6}"
  pause "Press Enter to mint JWT-SVID..."
fi

vault_headers+=(--header "X-Vault-Token: ${VAULT_TOKEN}")

# --- Step 2: Mint JWT-SVID from SPIFFE engine ---

info "Step 2/4: Mint JWT-SVID from ${SPIFFE_MOUNT}/role/${SPIFFE_ROLE}/mintjwt."

mint_payload="$(python3 -c '
import json
print(json.dumps({"audience": "api://AzureADTokenExchange"}))
')"

show_command \
  curl \
  --header "Content-Type: application/json" \
  ${VAULT_NAMESPACE:+--header "X-Vault-Namespace: ${VAULT_NAMESPACE}"} \
  --header "X-Vault-Token: [REDACTED]" \
  --request POST \
  --data '{"audience":"api://AzureADTokenExchange"}' \
  "${VAULT_ADDR%/}/v1/${SPIFFE_MOUNT}/role/${SPIFFE_ROLE}/mintjwt"

mint_response="$(
  curl_request \
    "${vault_headers[@]}" \
    --request POST \
    --data "${mint_payload}" \
    "${VAULT_ADDR%/}/v1/${SPIFFE_MOUNT}/role/${SPIFFE_ROLE}/mintjwt"
)"

jwt_svid="$(printf '%s' "${mint_response}" | json_get 'data.token')"
[[ -n "${jwt_svid}" ]] || fail "SPIFFE engine did not return a token"

info "JWT-SVID acquired."
printf '    JWT-SVID: %s\n' "${jwt_svid}"

decode_jwt "${jwt_svid}" "JWT-SVID"
pause "Press Enter to exchange JWT-SVID with Azure..."

# --- Step 3: Exchange JWT-SVID with Azure ---

info "Step 3/4: Exchange JWT-SVID for Azure access token."

exchange_data="grant_type=client_credentials"
exchange_data+="&client_id=$(url_encode "${AZURE_CLIENT_ID}")"
exchange_data+="&scope=$(url_encode "https://storage.azure.com/.default")"
exchange_data+="&client_assertion_type=$(url_encode "urn:ietf:params:oauth:client-assertion-type:jwt-bearer")"
exchange_data+="&client_assertion=$(url_encode "${jwt_svid}")"

show_command \
  curl \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --request POST \
  --data "grant_type=client_credentials&client_id=${AZURE_CLIENT_ID}&scope=https://storage.azure.com/.default&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=[REDACTED]" \
  "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token"

# Retry with backoff for FIC propagation delay
max_attempts=3
attempt=1
azure_token=""

while [[ ${attempt} -le ${max_attempts} ]]; do
  exchange_response="$(
    curl --silent --show-error \
      --output "${tmp_dir}/curl-response.json" \
      --write-out '%{http_code}' \
      --header "Content-Type: application/x-www-form-urlencoded" \
      --request POST \
      --data "${exchange_data}" \
      "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token"
  )"

  if [[ "${exchange_response}" =~ ^2 ]]; then
    azure_token="$(cat "${tmp_dir}/curl-response.json" | json_get 'access_token')"
    break
  fi

  # Check if it's a propagation-related error (AADSTS70021)
  if [[ ${attempt} -lt ${max_attempts} ]] && grep -q "AADSTS70021" "${tmp_dir}/curl-response.json" 2>/dev/null; then
    wait_seconds=$((attempt * 30))
    info "FIC may still be propagating (attempt ${attempt}/${max_attempts}). Waiting ${wait_seconds}s..."
    sleep "${wait_seconds}"
    attempt=$((attempt + 1))
  else
    if [[ -s "${tmp_dir}/curl-response.json" ]]; then
      cat "${tmp_dir}/curl-response.json" >&2
      printf '\n' >&2
    fi
    fail "Azure token exchange failed with HTTP ${exchange_response}"
  fi
done

[[ -n "${azure_token}" ]] || fail "Azure did not return an access token after ${max_attempts} attempts"

info "Azure access token acquired."
printf '    Azure token: %s...%s\n' "${azure_token:0:20}" "${azure_token: -10}"

decode_jwt "${azure_token}" "Azure access token"
pause "Press Enter to call Azure Storage API..."

# --- Step 4: Call Azure Storage API ---

info "Step 4/4: Call Azure Storage API (list containers) to verify end-to-end connectivity."

storage_url="https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/?comp=list"

show_command \
  curl \
  --header "Authorization: Bearer [REDACTED]" \
  --header "x-ms-version: 2021-08-06" \
  "${storage_url}"

storage_response="$(
  curl_request \
    --header "Authorization: Bearer ${azure_token}" \
    --header "x-ms-version: 2021-08-06" \
    "${storage_url}"
)"

info "Azure Storage API call succeeded."
if command -v xmllint &>/dev/null; then
  printf '    Response:\n'
  printf '%s' "${storage_response}" | xmllint --format - 2>/dev/null | sed 's/^/      /'
else
  printf '    Response (first 500 chars):\n'
  printf '      %s\n' "$(printf '%s' "${storage_response}" | head -c 500)"
fi

echo ""
info "Validation complete. The full WIF flow is working:"
info "  Vault (userpass) → JWT-SVID (SPIFFE) → Azure token exchange → Storage API"
