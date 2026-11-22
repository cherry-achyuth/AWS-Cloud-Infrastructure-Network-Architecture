# ==============================================================================
# Terraform & Provider Version Constraints
# ==============================================================================
# Pinning versions guarantees reproducible infrastructure deployments across
# different engineer machines and CI/CD pipelines.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
