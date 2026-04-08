resource "aws_security_group" "vault" {
  name        = "${local.name_prefix}-vault"
  description = "Security group for the Vault instance."
  vpc_id      = aws_vpc.sandpit.id

  tags = {
    Name    = "${local.name_prefix}-vault-sg"
    Service = "vault"
  }
}

resource "aws_vpc_security_group_egress_rule" "vault_all" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound traffic."
}

resource "aws_vpc_security_group_ingress_rule" "vault_ssh" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = local.selected_operator_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from the operator host."
}

resource "aws_vpc_security_group_ingress_rule" "vault_cluster" {
  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.vault.id
  from_port                    = 8201
  to_port                      = 8201
  ip_protocol                  = "tcp"
  description                  = "Vault cluster traffic within the security group."
}

resource "aws_security_group" "artifactory" {
  name        = "${local.name_prefix}-artifactory"
  description = "Security group for the Artifactory instance."
  vpc_id      = aws_vpc.sandpit.id

  tags = {
    Name    = "${local.name_prefix}-artifactory-sg"
    Service = "artifactory"
  }
}

resource "aws_vpc_security_group_egress_rule" "artifactory_all" {
  security_group_id = aws_security_group.artifactory.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound traffic."
}

resource "aws_vpc_security_group_ingress_rule" "artifactory_ssh" {
  security_group_id = aws_security_group.artifactory.id
  cidr_ipv4         = local.selected_operator_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from the operator host."
}
