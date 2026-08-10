terraform {
  # optional() object attribute defaults require Terraform >= 1.3.
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
  }

  # No backend block on purpose: `terraform init -backend=false && terraform validate`
  # must work offline (mirrors the offline `bicep build` CI check).
}

provider "azurerm" {
  features {}
}

provider "azapi" {
}
