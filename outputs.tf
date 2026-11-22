# ==============================================================================
# Outputs
# ==============================================================================
# Exposes essential resource identifiers for verification, downstream modules,
# or integration with deployment pipelines.

output "vpc_id" {
  description = "The ID of the created Virtual Private Cloud"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The primary CIDR block associated with the VPC"
  value       = aws_vpc.main.cidr_block
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway attached to the VPC"
  value       = aws_internet_gateway.main.id
}

output "public_subnet_ids" {
  description = "List of IDs of the public subnets across Availability Zones"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets across Availability Zones"
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "The ID of the public route table associated with public subnets"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "The ID of the private route table associated with private subnets"
  value       = aws_route_table.private.id
}

output "web_security_group_id" {
  description = "The ID of the public web tier security group"
  value       = aws_security_group.web.id
}

output "private_app_security_group_id" {
  description = "The ID of the private application tier security group"
  value       = aws_security_group.private_app.id
}

# ------------------------------------------------------------------------------
# Conditional Compute Outputs
# ------------------------------------------------------------------------------
# Only populated when var.enable_ec2_instance is true.

output "ec2_instance_id" {
  description = "The instance ID of the demo EC2 web server (if enabled)"
  value       = var.enable_ec2_instance ? aws_instance.demo_web[0].id : "EC2 deployment disabled (var.enable_ec2_instance = false)"
}

output "ec2_public_ip" {
  description = "The public IPv4 address of the demo EC2 web server (if enabled)"
  value       = var.enable_ec2_instance ? aws_instance.demo_web[0].public_ip : "EC2 deployment disabled (var.enable_ec2_instance = false)"
}

output "ec2_public_dns" {
  description = "The public DNS hostname of the demo EC2 web server (if enabled)"
  value       = var.enable_ec2_instance ? aws_instance.demo_web[0].public_dns : "EC2 deployment disabled (var.enable_ec2_instance = false)"
}

output "demo_web_url" {
  description = "Direct HTTP URL to test the demo web application (if enabled)"
  value       = var.enable_ec2_instance ? "http://${aws_instance.demo_web[0].public_ip}" : "N/A"
}
