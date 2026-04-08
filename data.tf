data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_route53_zone" "selected" {
  name         = "${local.zone_name}."
  private_zone = false
}

data "aws_key_pair" "operator" {
  key_name = var.ssh_key_name
}

data "http" "current_ip" {
  count = var.operator_cidr == null ? 1 : 0
  url   = "https://checkip.amazonaws.com/"
}

data "aws_ami" "hc-base-ubuntu-2404" {
  for_each = toset(["amd64", "arm64"])

  filter {
    name   = "name"
    values = [format("hc-base-ubuntu-2404-%s-*", each.value)]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  most_recent = true
  owners      = ["888995627335"]
}

data "aws_ami" "hc_base_rhel_9" {
  for_each    = toset(["x86_64", "arm64"])
  most_recent = true
  owners      = [var.rhel_ami_owner]

  filter {
    name   = "name"
    values = ["hc-base-rhel-9-${each.key}-*"]
  }
}

data "aws_iam_policy_document" "vault_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "vault_kms" {
  statement {
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = [aws_kms_key.vault_unseal.arn]
  }
}
