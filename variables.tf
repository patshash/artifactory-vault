variable "aws_region" {
  description = "AWS region for the sandpit deployment."
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = var.aws_region == "ap-southeast-2"
    error_message = "This configuration currently targets the AWS Sydney region (ap-southeast-2)."
  }
}

variable "environment_name" {
  description = "Environment name used in resource naming and tagging."
  type        = string
  default     = "sandpit"
}

variable "instance_architecture" {
  description = "Architecture used to select the base AMI and compatible instance families."
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.instance_architecture)
    error_message = "instance_architecture must be either amd64 or arm64."
  }
}

variable "rhel_ami_owner" {
  description = "AWS account ID that owns the hc-base-rhel-9 AMIs used for the Artifactory node."
  type        = string
  default     = "888995627335"
}

variable "ssh_key_name" {
  description = "Existing AWS EC2 key pair name used for SSH access."
  type        = string
}

variable "route53_zone_name" {
  description = "Pre-existing public Route53 hosted zone used for service records."
  type        = string
}

variable "vault_dns_label" {
  description = "Relative DNS label for the Vault service record."
  type        = string
  default     = "vault"
}

variable "artifactory_dns_label" {
  description = "Relative DNS label for the Artifactory service record."
  type        = string
  default     = "artifactory"
}

variable "operator_cidr" {
  description = "CIDR block allowed to reach Vault, Artifactory, and SSH. Leave null to auto-detect the current public IP."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.operator_cidr == null || (can(cidrhost(var.operator_cidr, 0)) && can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+/\\d+$", var.operator_cidr)))
    error_message = "operator_cidr must be null or a valid IPv4 CIDR block."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the new sandpit VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets used by the Vault and Artifactory instances."
  type        = list(string)
  default     = ["10.42.10.0/24", "10.42.20.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2 && alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Provide at least two valid subnet CIDR blocks."
  }
}

variable "vault_instance_type" {
  description = "Optional override for the Vault EC2 instance type."
  type        = string
  default     = null
  nullable    = true
}

variable "artifactory_instance_type" {
  description = "Optional override for the Artifactory EC2 instance type."
  type        = string
  default     = null
  nullable    = true
}

variable "vault_root_volume_size" {
  description = "Vault root volume size in GiB."
  type        = number
  default     = 40

  validation {
    condition     = var.vault_root_volume_size >= 20
    error_message = "vault_root_volume_size must be at least 20 GiB."
  }
}

variable "artifactory_root_volume_size" {
  description = "Artifactory root volume size in GiB."
  type        = number
  default     = 150

  validation {
    condition     = var.artifactory_root_volume_size >= 100
    error_message = "artifactory_root_volume_size must be at least 100 GiB."
  }
}

variable "artifactory_oss_rpm_url" {
  description = "URL for the published JFrog Artifactory OSS RPM used for the RHEL package-manager installation."
  type        = string
  default     = "https://releases.jfrog.io/artifactory/jfrog-rpms/jfrog-artifactory-oss/jfrog-artifactory-oss-5.10.0.rpm"
}

variable "common_tags" {
  description = "Additional tags applied to all managed resources."
  type        = map(string)
  default     = {}
}
