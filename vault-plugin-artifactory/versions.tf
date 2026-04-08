terraform {
  required_version = ">= 1.5.0"

  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}
