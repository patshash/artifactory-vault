resource "aws_kms_key" "vault_unseal" {
  description             = "Vault auto-unseal key for ${local.name_prefix}."
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name    = "${local.name_prefix}-vault-unseal"
    Service = "vault"
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${local.name_prefix}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

resource "aws_iam_role" "vault" {
  name               = "${local.name_prefix}-vault-role"
  assume_role_policy = data.aws_iam_policy_document.vault_assume_role.json

  tags = {
    Name    = "${local.name_prefix}-vault-role"
    Service = "vault"
  }
}

resource "aws_iam_role_policy" "vault_kms" {
  name   = "${local.name_prefix}-vault-kms"
  role   = aws_iam_role.vault.id
  policy = data.aws_iam_policy_document.vault_kms.json
}

resource "aws_iam_instance_profile" "vault" {
  name = "${local.name_prefix}-vault-profile"
  role = aws_iam_role.vault.name
}
