# ==============================================================================
# Security Groups: Tiered Ingress & Egress Controls
# ==============================================================================
# Implements the Principle of Least Privilege at the Elastic Network Interface (ENI)
# layer using stateful Security Groups.
#
# Key Concepts:
# - Stateful: Return traffic is automatically allowed regardless of outbound rules.
# - Explicit Trust: The private tier trusts the public tier via Security Group ID
#   referencing (chaining), NOT via broad IP CIDR ranges.

# ------------------------------------------------------------------------------
# 1. Public Tier Security Group (Web / Administrative Access)
# ------------------------------------------------------------------------------
# Attached to resources in public subnets (such as the optional demo web server).
resource "aws_security_group" "web" {
  name        = "${local.name_prefix}-web-sg"
  description = "Controls ingress and egress traffic for public-facing web instances"
  vpc_id      = aws_vpc.main.id

  # Ingress: Allow inbound HTTP from the internet for web application testing
  ingress {
    description = "Allow inbound HTTP traffic for web application demo"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress: Administrative SSH (Port 22)
  # Dynamic block: Activated ONLY when a trusted IP CIDR is provided in var.admin_ssh_cidr.
  # If left empty, SSH ingress is completely disabled.
  dynamic "ingress" {
    for_each = var.admin_ssh_cidr != "" ? [var.admin_ssh_cidr] : []
    content {
      description = "Administrative SSH access restricted to trusted administrator IP"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # Egress: Allow outbound connectivity so the instance can download security
  # patches, install packages via dnf/yum, and respond statefully to clients.
  egress {
    description = "Allow all outbound traffic for software updates and client responses"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-web-sg"
    Tier = "Public"
  }
}

# ------------------------------------------------------------------------------
# 2. Private Tier Security Group (Backend Workloads & Databases)
# ------------------------------------------------------------------------------
# Attached to future internal resources (app servers, databases) in private subnets.
#
# IMPORTANT ARCHITECTURAL PRACTICE:
# This security group demonstrates "Security Group Chaining". Ingress is not permitted
# from an IP CIDR block; instead, it is restricted strictly to network interfaces that
# carry the Web Security Group ID (aws_security_group.web.id).
resource "aws_security_group" "private_app" {
  name        = "${local.name_prefix}-private-app-sg"
  description = "Controls ingress and egress traffic for internal private tier workloads"
  vpc_id      = aws_vpc.main.id

  # Ingress: Internal application traffic strictly originating from the Web tier.
  # Port 8080 represents internal application/API service port.
  ingress {
    description     = "Allow internal API traffic strictly from instances in the Web Security Group"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  # Egress: Restrict private tier outbound traffic strictly to within the local VPC.
  # Private resources cannot reach the internet directly.
  egress {
    description = "Allow outbound communication only to internal VPC resources"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${local.name_prefix}-private-app-sg"
    Tier = "Private"
  }
}
