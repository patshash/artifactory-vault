output "operator_cidr" {
  description = "CIDR that is allowed to reach SSH and the HTTPS load balancer."
  value       = local.selected_operator_cidr
}

output "vault_url" {
  description = "Vault service URL."
  value       = local.vault_url
}

output "vault_public_ip" {
  description = "Elastic IP assigned to the Vault instance."
  value       = aws_eip.vault.public_ip
}

output "vault_instance_architecture" {
  description = "Instance architecture used for the Vault node and compatible plugin binaries."
  value       = var.instance_architecture
}

output "vault_ssh_command" {
  description = "Convenience SSH command for the Vault instance."
  value       = "ssh ubuntu@${aws_eip.vault.public_ip}"
}

output "artifactory_url" {
  description = "Artifactory service URL."
  value       = local.artifactory_url
}

output "artifactory_public_ip" {
  description = "Elastic IP assigned to the Artifactory instance."
  value       = aws_eip.artifactory.public_ip
}

output "artifactory_ssh_command" {
  description = "Convenience SSH command for the Artifactory instance."
  value       = "ssh ec2-user@${aws_eip.artifactory.public_ip}"
}

output "vault_initialization_hint" {
  description = "Command to initialize Vault after the service is up."
  value       = "ssh ubuntu@${aws_eip.vault.public_ip} 'sudo VAULT_ADDR=http://127.0.0.1:8200 vault operator init'"
}
