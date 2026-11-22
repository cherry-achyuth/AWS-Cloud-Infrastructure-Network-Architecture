# ==============================================================================
# Main Orchestration & Local Values
# ==============================================================================
# Defines local computed values and shared metadata tags applied across all
# AWS resources in this project.

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Repository  = "aws-cloud-network-architecture"
  }
}
