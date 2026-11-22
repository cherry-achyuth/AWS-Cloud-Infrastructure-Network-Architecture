# ==============================================================================
# Input Variables
# ==============================================================================
# Variables parameterize the infrastructure, avoiding hardcoded values and
# enabling environment reusability (dev, staging, prod).

variable "aws_region" {
  description = "The target AWS Region for all resources. Defaults to Mumbai (ap-south-1)."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name prefix used for resource naming and tagging."
  type        = string
  default     = "aws-network-architecture"
}

variable "environment" {
  description = "Target environment name (e.g., dev, test, staging, prod)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "The CIDR block allocated to the Virtual Private Cloud (VPC)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "The vpc_cidr must be a valid IPv4 CIDR block (e.g., 10.0.0.0/16)."
  }
}

variable "availability_zones" {
  description = "List of two Availability Zones within the region for multi-AZ high availability."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two Availability Zones must be specified for multi-AZ resilience."
  }
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for the public subnets (one per Availability Zone)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2 && alltrue([for c in var.public_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "At least two valid IPv4 CIDR blocks must be provided for public subnets."
  }
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for the private subnets (one per Availability Zone)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2 && alltrue([for c in var.private_subnet_cidrs : can(cidrnetmask(c))])
    error_message = "At least two valid IPv4 CIDR blocks must be provided for private subnets."
  }
}

variable "enable_ec2_instance" {
  description = "Flag to conditionally provision a demo EC2 Linux instance in a public subnet. Disabled by default to prevent unexpected compute costs."
  type        = bool
  default     = false
}

variable "ec2_instance_type" {
  description = "EC2 instance type for the optional demo instance (Free Tier eligible: t2.micro or t3.micro in ap-south-1)."
  type        = string
  default     = "t2.micro"
}

variable "admin_ssh_cidr" {
  description = "Trusted administrative IP address in CIDR notation (e.g., 203.0.113.50/32) permitted to SSH into the demo EC2 instance. Leave empty to disable SSH ingress entirely."
  type        = string
  default     = ""

  validation {
    condition     = var.admin_ssh_cidr == "" || (can(cidrnetmask(var.admin_ssh_cidr)) && var.admin_ssh_cidr != "0.0.0.0/0")
    error_message = "The admin_ssh_cidr must either be empty or a valid CIDR block (e.g. 203.0.113.50/32). Unrestricted 0.0.0.0/0 is strictly prohibited for security."
  }
}

variable "ec2_key_name" {
  description = "Name of an existing AWS Key Pair to associate with the demo EC2 instance for SSH access. Leave empty if no key pair is used."
  type        = string
  default     = ""
}
