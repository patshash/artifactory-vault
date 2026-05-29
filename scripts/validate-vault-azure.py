#!/usr/bin/env python3
"""
Authenticates to Vault, mints a SPIFFE JWT-SVID, exchanges it with Microsoft
Entra ID for an Azure access token, and calls the Azure Storage API to validate
end-to-end Workload Identity Federation.

Uses the Azure SDK (azure-identity + azure-storage-blob) with
ClientAssertionCredential for automatic token exchange and caching.

Inputs can be provided as CLI flags or environment variables.

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
"""

import argparse
import base64
import json
import os
import sys
import time
from datetime import datetime, timezone
from getpass import getpass
from urllib.parse import quote

import requests
from azure.identity import ClientAssertionCredential
from azure.storage.blob import BlobServiceClient


def info(msg: str) -> None:
    print(f"==> {msg}")


def fail(msg: str) -> None:
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(1)


def decode_jwt(token: str, label: str = "JWT") -> dict:
    """Decode and display a JWT token's header and payload."""
    parts = token.split(".")
    if len(parts) < 2:
        fail(f"Invalid JWT: expected at least 2 parts, got {len(parts)}")

    def decode_part(b64: str) -> dict:
        padding = 4 - len(b64) % 4
        if padding != 4:
            b64 += "=" * padding
        return json.loads(base64.urlsafe_b64decode(b64))

    header = decode_part(parts[0])
    payload = decode_part(parts[1])

    print(f"    {label} header:")
    print(f"      {json.dumps(header, indent=2).replace(chr(10), chr(10) + '      ')}")
    print(f"    {label} payload:")
    print(f"      {json.dumps(payload, indent=2).replace(chr(10), chr(10) + '      ')}")

    for field in ("iat", "exp", "nbf"):
        if field in payload:
            ts = datetime.fromtimestamp(payload[field], tz=timezone.utc)
            print(f"      ({field}: {ts.isoformat()})")

    return payload


def pause(msg: str = "Press Enter to continue...") -> None:
    input(f"\n    {msg}")
    print()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate Vault → SPIFFE → Azure WIF end-to-end flow."
    )
    parser.add_argument("--vault-addr", default=os.environ.get("VAULT_ADDR"))
    parser.add_argument("--vault-token", default=os.environ.get("VAULT_TOKEN"))
    parser.add_argument("--vault-username", default=os.environ.get("VAULT_USERNAME"))
    parser.add_argument("--vault-password", default=os.environ.get("VAULT_PASSWORD"))
    parser.add_argument("--vault-namespace", default=os.environ.get("VAULT_NAMESPACE", ""))
    parser.add_argument("--vault-auth-path", default=os.environ.get("VAULT_AUTH_PATH", "userpass"))
    parser.add_argument("--spiffe-role", default=os.environ.get("SPIFFE_ROLE", "azure-wif"))
    parser.add_argument("--spiffe-mount", default=os.environ.get("SPIFFE_MOUNT", "spiffe"))
    parser.add_argument("--azure-tenant-id", default=os.environ.get("AZURE_TENANT_ID"))
    parser.add_argument("--azure-client-id", default=os.environ.get("AZURE_CLIENT_ID"))
    parser.add_argument("--storage-account", default=os.environ.get("AZURE_STORAGE_ACCOUNT"))
    return parser.parse_args()


class VaultClient:
    """Minimal Vault HTTP client for userpass auth and SPIFFE JWT minting."""

    def __init__(self, addr: str, namespace: str = ""):
        self.addr = addr.rstrip("/")
        self.namespace = namespace.strip("/")
        self.token: str | None = None
        self.session = requests.Session()
        self.session.headers["Content-Type"] = "application/json"
        if self.namespace:
            self.session.headers["X-Vault-Namespace"] = self.namespace

    def _url(self, path: str) -> str:
        return f"{self.addr}/v1/{path.lstrip('/')}"

    def _request(self, method: str, path: str, **kwargs) -> dict:
        resp = self.session.request(method, self._url(path), **kwargs)
        if not resp.ok:
            fail(f"Vault {method} {path} failed ({resp.status_code}): {resp.text}")
        return resp.json()

    def login_userpass(self, username: str, password: str) -> str:
        encoded_user = quote(username, safe="")
        path = f"auth/userpass/login/{encoded_user}"
        info(f"Step 1/4: Authenticate to Vault (userpass: {username}).")
        print(f"    POST {self._url(path)}")

        data = self._request("POST", path, json={"password": password})
        self.token = data["auth"]["client_token"]
        self.session.headers["X-Vault-Token"] = self.token

        info("Vault login succeeded.")
        print(f"    Vault token: {self.token[:10]}...{self.token[-6:]}")
        return self.token

    def set_token(self, token: str) -> None:
        self.token = token
        self.session.headers["X-Vault-Token"] = token

    def mint_jwt_svid(self, mount: str, role: str) -> str:
        path = f"{mount}/role/{role}/mintjwt"
        info(f"Step 2/4: Mint JWT-SVID from {path}.")
        print(f"    POST {self._url(path)}")

        data = self._request("POST", path, json={"audience": "api://AzureADTokenExchange"})
        token = data["data"]["token"]

        if not token:
            fail("SPIFFE engine did not return a token")

        info("JWT-SVID acquired.")
        print(f"    JWT-SVID: {token[:40]}...{token[-20:]}")
        decode_jwt(token, "JWT-SVID")
        return token


def validate_storage(credential, storage_account: str) -> None:
    """Call Azure Storage API to verify end-to-end connectivity."""
    info("Step 4/4: Call Azure Storage API (list containers) to verify end-to-end connectivity.")

    account_url = f"https://{storage_account}.blob.core.windows.net"
    print(f"    GET {account_url}/?comp=list")

    blob_service = BlobServiceClient(account_url=account_url, credential=credential)
    containers = list(blob_service.list_containers(results_per_page=5))

    info("Azure Storage API call succeeded.")
    print(f"    Containers found: {len(containers)}")
    for c in containers[:5]:
        print(f"      - {c['name']}")


def main() -> None:
    args = parse_args()

    # Validate required inputs
    if not args.vault_addr:
        fail("VAULT_ADDR or --vault-addr is required")
    if not args.azure_tenant_id:
        fail("AZURE_TENANT_ID or --azure-tenant-id is required")
    if not args.azure_client_id:
        fail("AZURE_CLIENT_ID or --azure-client-id is required")
    if not args.storage_account:
        fail("AZURE_STORAGE_ACCOUNT or --storage-account is required")

    info("Starting Azure WIF validation.")
    info("This script will authenticate to Vault, mint a SPIFFE JWT-SVID, exchange it with Azure, and call the Storage API.")

    # --- Step 1: Authenticate to Vault ---
    vault = VaultClient(args.vault_addr, args.vault_namespace)

    if args.vault_token:
        info("Step 1/4: Reuse the provided Vault token.")
        vault.set_token(args.vault_token)
    else:
        username = args.vault_username
        password = args.vault_password
        if not username:
            username = input("Vault username: ")
        if not password:
            password = getpass("Vault password: ")
        vault.login_userpass(username, password)
        pause("Press Enter to mint JWT-SVID...")

    # --- Step 2: Mint JWT-SVID ---
    jwt_svid = vault.mint_jwt_svid(args.spiffe_mount, args.spiffe_role)
    pause("Press Enter to exchange JWT-SVID with Azure...")

    # --- Step 3: Exchange JWT-SVID with Azure using ClientAssertionCredential ---
    info("Step 3/4: Exchange JWT-SVID for Azure access token (via ClientAssertionCredential).")

    def get_assertion() -> str:
        """Callback that returns the current JWT-SVID as the client assertion."""
        return jwt_svid

    credential = ClientAssertionCredential(
        tenant_id=args.azure_tenant_id,
        client_id=args.azure_client_id,
        func=get_assertion,
    )

    # Force a token acquisition to validate the exchange works
    token_response = credential.get_token("https://storage.azure.com/.default")
    info("Azure access token acquired.")
    print(f"    Azure token: {token_response.token[:20]}...{token_response.token[-10:]}")
    decode_jwt(token_response.token, "Azure access token")
    pause("Press Enter to call Azure Storage API...")

    # --- Step 4: Call Azure Storage API ---
    validate_storage(credential, args.storage_account)

    print()
    info("Validation complete. The full WIF flow is working:")
    info("  Vault (userpass) → JWT-SVID (SPIFFE) → Azure token exchange → Storage API")


if __name__ == "__main__":
    main()
