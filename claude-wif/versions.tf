terraform {
  required_version = ">= 1.5.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.8"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

  }
}
