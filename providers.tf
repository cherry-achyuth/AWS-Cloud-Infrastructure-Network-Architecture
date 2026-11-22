# ==============================================================================
# AWS Provider Configuration
# ==============================================================================
# Configures the AWS provider region and applies default tags to all resources
# managed by this project for unified cost allocation and governance.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
