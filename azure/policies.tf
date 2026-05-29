# --- Vault policy for SPIFFE JWT-SVID minting ---

resource "vault_policy" "azure_spiffe_user" {
  name   = "azure-spiffe-user"
  policy = file("${path.module}/azure-spiffe-user-policy.hcl")
}
