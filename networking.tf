# ==============================================================================
# Networking Infrastructure: VPC, Subnets, Gateways & Route Tables
# ==============================================================================
# Implements a Dual-Tier Multi-AZ AWS network architecture.
#
# Key Architectural Decisions:
# 1. Multi-AZ: Subnets span two distinct Availability Zones for resilience.
# 2. Public Subnets: Have a direct route to the Internet Gateway (0.0.0.0/0 -> IGW).
# 3. Private Subnets: Completely isolated from the internet (no route to IGW).
# 4. Cost Protection: NAT Gateway is intentionally omitted to avoid idle charges
#    (~$32.40/month per NAT Gateway).

# ------------------------------------------------------------------------------
# 1. Virtual Private Cloud (VPC)
# ------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # Enables internal AWS DNS resolution
  enable_dns_hostnames = true # Assigns public/private DNS hostnames to instances

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# ------------------------------------------------------------------------------
# 2. Internet Gateway (IGW)
# ------------------------------------------------------------------------------
# Provides horizontally scaled, redundant internet connectivity for public subnets.
# Performs 1:1 NAT translation between private IP on the ENI and the public IP.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# ------------------------------------------------------------------------------
# 3. Public Subnets (Multi-AZ)
# ------------------------------------------------------------------------------
# Instances launched here automatically receive a public IPv4 address and can be
# reached from the internet if permitted by Security Groups and Route Tables.
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Tier = "Public"
    AZ   = var.availability_zones[count.index]
  }
}

# ------------------------------------------------------------------------------
# 4. Private Subnets (Multi-AZ)
# ------------------------------------------------------------------------------
# Backend workloads, databases, and internal services reside here.
# Instances launched here never receive public IP addresses and have no direct path
# to or from the public internet.
resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Tier = "Private"
    AZ   = var.availability_zones[count.index]
  }
}

# ------------------------------------------------------------------------------
# 5. Public Route Table & Routing
# ------------------------------------------------------------------------------
# Directs default egress traffic (0.0.0.0/0) to the Internet Gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
    Tier = "Public"
  }
}

# Explicitly associate each public subnet with the public route table
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ------------------------------------------------------------------------------
# 6. Private Route Table & Routing
# ------------------------------------------------------------------------------
# Contains only the default local VPC route (e.g. 10.0.0.0/16 -> local).
# No default route to the IGW exists, ensuring total isolation from the internet.
#
# NOTE FOR PRODUCTION ENHANCEMENT:
# To grant private subnets outbound-only access (for OS patching, package downloads),
# you would provision an AWS NAT Gateway in a public subnet and add:
#   route {
#     cidr_block     = "0.0.0.0/0"
#     nat_gateway_id = aws_nat_gateway.example.id
#   }
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-private-rt"
    Tier = "Private"
  }
}

# Explicitly associate each private subnet with the private route table
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
