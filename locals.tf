locals {
  zone_name = trimsuffix(var.route53_zone_name, ".")

  name_prefix = "user-${var.environment_name}"

  default_instance_types = {
    amd64 = {
      vault       = "t3.small"
      artifactory = "t3.xlarge"
    }
    arm64 = {
      vault       = "t4g.small"
      artifactory = "t4g.xlarge"
    }
  }

  selected_operator_cidr = var.operator_cidr != null ? var.operator_cidr : format("%s/32", chomp(data.http.current_ip[0].response_body))

  artifactory_rhel_architecture = var.instance_architecture == "amd64" ? "x86_64" : "arm64"

  selected_vault_instance_type       = coalesce(var.vault_instance_type, local.default_instance_types[var.instance_architecture].vault)
  selected_artifactory_instance_type = coalesce(var.artifactory_instance_type, local.default_instance_types[var.instance_architecture].artifactory)

  availability_zones = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))

  deployment_subnet_keys = {
    vault       = "0"
    artifactory = "0"
  }

  vault_fqdn       = "${var.vault_dns_label}.${local.zone_name}"
  artifactory_fqdn = "${var.artifactory_dns_label}.${local.zone_name}"

  vault_url       = "https://${local.vault_fqdn}"
  artifactory_url = "https://${local.artifactory_fqdn}"

  common_tags = merge(
    {
      Environment = var.environment_name
      ManagedBy   = "terraform"
      Project     = "artifactory-vault"
    },
    var.common_tags,
  )
}
