terraform {
  required_version = ">= 1.6.0"

  cloud {
    organization = "KAIROSYNQ-ANALYTIX"

    workspaces {
      name = "terraform-infra"
    }
  }

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.55"
    }
  }
}

# Auth: run `terraform login` locally (stores token in
# ~/.terraform.d/credentials.tfrc.json). No token here.
provider "tfe" {}

data "tfe_organization" "this" {
  name = "KAIROSYNQ-ANALYTIX"
}
