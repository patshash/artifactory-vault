resource "aws_instance" "vault" {
  ami                         = data.aws_ami.hc-base-ubuntu-2404[var.instance_architecture].id
  associate_public_ip_address = true
  instance_type               = local.selected_vault_instance_type
  subnet_id                   = aws_subnet.public[local.deployment_subnet_keys.vault].id
  vpc_security_group_ids      = [aws_security_group.vault.id]
  iam_instance_profile        = aws_iam_instance_profile.vault.name
  key_name                    = data.aws_key_pair.operator.key_name
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/templates/vault-user-data.sh.tftpl", {
    aws_region = var.aws_region
    kms_key_id = aws_kms_key.vault_unseal.key_id
    node_name  = "${local.name_prefix}-vault-1"
    vault_fqdn = local.vault_fqdn
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.vault_root_volume_size
    volume_type           = "gp3"
  }

  tags = {
    Name    = "${local.name_prefix}-vault-1"
    Service = "vault"
  }

  depends_on = [aws_iam_role_policy.vault_kms]
}

resource "aws_eip" "vault" {
  domain = "vpc"

  tags = {
    Name    = "${local.name_prefix}-vault-eip"
    Service = "vault"
  }
}

resource "aws_eip_association" "vault" {
  allocation_id = aws_eip.vault.id
  instance_id   = aws_instance.vault.id
}

resource "aws_instance" "artifactory" {
  ami                         = data.aws_ami.hc_base_rhel_9[local.artifactory_rhel_architecture].id
  associate_public_ip_address = true
  instance_type               = local.selected_artifactory_instance_type
  subnet_id                   = aws_subnet.public[local.deployment_subnet_keys.artifactory].id
  vpc_security_group_ids      = [aws_security_group.artifactory.id]
  key_name                    = data.aws_key_pair.operator.key_name
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/templates/artifactory-user-data.sh.tftpl", {
    artifactory_oss_rpm_url = var.artifactory_oss_rpm_url
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.artifactory_root_volume_size
    volume_type           = "gp3"
  }

  tags = {
    Name    = "${local.name_prefix}-artifactory-1"
    Service = "artifactory"
  }
}

resource "aws_eip" "artifactory" {
  domain = "vpc"

  tags = {
    Name    = "${local.name_prefix}-artifactory-eip"
    Service = "artifactory"
  }
}

resource "aws_eip_association" "artifactory" {
  allocation_id = aws_eip.artifactory.id
  instance_id   = aws_instance.artifactory.id
}
