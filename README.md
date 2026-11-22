# AWS Cloud Infrastructure & Network Architecture

[![Terraform](https://img.shields.io/badge/IaC-Terraform_v1.5+-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/AWS_Provider-v5.0+-FF9900?logo=amazon-aws&logoColor=white)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![Region](https://img.shields.io/badge/AWS_Region-ap--south--1_(Mumbai)-232F3E?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An enterprise-ready, cost-conscious, multi-AZ **Virtual Private Cloud (VPC)** and network security infrastructure implemented as code using **Terraform**.

This project demonstrates the core networking, compute, security, and operational practices expected of a modern **AWS Cloud Operations / Infrastructure Automation Engineer**.

---

## Architecture Diagram

```mermaid
flowchart TB
    subgraph Internet ["Public Internet"]
        Client["External Client (HTTP Port 80)"]
        Admin["Administrator (SSH Port 22 - Trusted IP)"]
    end

    subgraph AWSCloud ["AWS Cloud (Region: ap-south-1 Mumbai)"]
        subgraph VPC ["Amazon VPC (CIDR: 10.0.0.0/16)"]
            IGW["Internet Gateway (IGW)<br/>Performs 1:1 NAT for Public Traffic"]

            subgraph AZ1 ["Availability Zone: ap-south-1a"]
                subgraph PublicSubnet1 ["Public Subnet 1 (10.0.1.0/24)"]
                    DemoEC2["Optional Demo Web Server<br/>(t2.micro / Amazon Linux 2023)<br/>[var.enable_ec2_instance]"]
                    WebSG["Web Security Group<br/>- HTTP (80): 0.0.0.0/0<br/>- SSH (22): admin_ssh_cidr<br/>- Outbound: 0.0.0.0/0"]
                end

                subgraph PrivateSubnet1 ["Private Subnet 1 (10.0.11.0/24)"]
                    PrivateWorkload1["Internal Workload / Database<br/>(Completely Isolated)"]
                    PrivateSG["Private App Security Group<br/>- Ingress: Port 8080 from Web SG<br/>- Outbound: Local VPC Only"]
                end
            end

            subgraph AZ2 ["Availability Zone: ap-south-1b"]
                subgraph PublicSubnet2 ["Public Subnet 2 (10.0.2.0/24)"]
                    PublicStandby["Reserved for High Availability<br/>(Application Load Balancer)"]
                end

                subgraph PrivateSubnet2 ["Private Subnet 2 (10.0.12.0/24)"]
                    PrivateWorkload2["Standby Workload / Replica DB"]
                end
            end

            subgraph RoutingTables ["Route Tables (Longest Prefix Match)"]
                PublicRT["Public Route Table<br/>- 10.0.0.0/16 ➔ local<br/>- 0.0.0.0/0 ➔ igw-xxxx"]
                PrivateRT["Private Route Table<br/>- 10.0.0.0/16 ➔ local<br/>(No route to IGW)"]
            end
        end
    end

    Client -->|HTTP: 80| IGW
    Admin -->|SSH: 22 (Whitelisted IP)| IGW
    IGW --> PublicRT
    PublicRT --> PublicSubnet1
    PublicRT --> PublicSubnet2
    DemoEC2 -.->|Chained Ingress| PrivateSG
    PrivateRT --> PrivateSubnet1
    PrivateRT --> PrivateSubnet2
```

---

## Business Problem & Architectural Goal

Organizations moving workloads to AWS require network architectures that satisfy three core requirements simultaneously:
1. **High Availability**: Resilience against data center failures by spreading resources across multiple Availability Zones.
2. **Defense-in-Depth Security**: Public-facing tiers must be segmented from sensitive private databases and backend workloads. Insecure administrative exposure (such as unrestricted SSH) must be prevented.
3. **Cost Governance**: Infrastructure must be free from accidental recurring costs (e.g., idle NAT Gateways or unmanaged public IPv4 addresses).

This project provides a clean, production-grade Terraform template that deploys a dual-tier VPC across two Availability Zones in **ap-south-1 (Mumbai)**, with zero idle compute or NAT gateway costs by default.

---

## AWS Services Used

- **Amazon VPC**: Isolated virtual cloud network with a `/16` CIDR block (`10.0.0.0/16`).
- **Amazon VPC Subnets**:
  - 2 Public Subnets across 2 Availability Zones (`ap-south-1a`, `ap-south-1b`).
  - 2 Private Subnets across 2 Availability Zones (`ap-south-1a`, `ap-south-1b`).
- **Amazon VPC Internet Gateway (IGW)**: Scalable gateway connecting public subnets to the internet with 1:1 NAT.
- **Amazon VPC Route Tables**: Explicit route tables and subnet associations managing network traffic using Longest Prefix Match (LPM).
- **Amazon VPC Security Groups**: Stateful, least-privilege firewalls at the Elastic Network Interface (ENI) level.
- **Amazon EC2 (Optional)**: Free-Tier eligible Linux compute instance running Amazon Linux 2023 with an automated HTTP status page and IMDSv2 protection.

---

## Key Design & Security Decisions

| Design Decision | Implementation | Why It Matters |
| :--- | :--- | :--- |
| **Multi-AZ Architecture** | 2 Availability Zones (`ap-south-1a`, `ap-south-1b`) | Satisfies AWS High Availability standards; allows seamless attachment of Application Load Balancers. |
| **Cost-First Default** | `enable_ec2_instance = false` | Prevents accidental compute charges until deployment is explicitly required. |
| **No Idle NAT Gateways** | Private subnets route to `local` only | Avoids the **\$32.40/month baseline charge** per NAT Gateway. Clear pattern provided for production expansion. |
| **No Open SSH Access** | `admin_ssh_cidr` parameter with validation | Completely prevents `0.0.0.0/0` exposure on port 22. SSH is disabled unless a trusted IP is provided. |
| **Security Group Chaining** | Private SG ingress restricted to `web_sg.id` | Private resources do not trust broad IP ranges; only instances carrying the Web SG identity can connect. |
| **IMDSv2 Enforced** | `http_tokens = "required"` | Protects the EC2 instance against Server-Side Request Forgery (SSRF) and metadata credential theft. |
| **No Hardcoded Secrets** | Credentials managed via standard AWS CLI / IAM | Terraform state files, keys, and credentials are strictly excluded via `.gitignore`. |

---

## Repository Structure

```text
aws-cloud-network-architecture/
│
├── README.md                 # Project overview, architectural decisions, and runbook
├── versions.tf               # Terraform core and AWS provider version constraints
├── providers.tf              # AWS provider configuration and global resource tagging
├── variables.tf              # Input variables with types, defaults, and validation rules
├── main.tf                   # Local values and naming conventions
├── networking.tf             # VPC, Subnets, IGW, Route Tables, and Subnet Associations
├── security.tf               # Tiered Security Groups (Web and Private App)
├── compute.tf                # Optional EC2 demo instance, AMI lookup, and User Data bootstrap
├── outputs.tf                # VPC, Subnet, Route Table, and conditional EC2 details
├── terraform.tfvars.example  # Example variable definitions for customization
├── .gitignore                # Protects sensitive files (*.tfstate, *.tfvars, *.pem)
│
├── docs/
│   └── learning-notes.md     # In-depth study guide: packet flow, NAT costs, and interview FAQs
│
└── diagrams/
    └── architecture.mmd      # Standalone Mermaid diagram source
```

---

## Prerequisites

Before running the project, ensure you have:
1. **AWS CLI** installed and configured:
   ```bash
   aws configure
   ```
2. **Terraform CLI (>= 1.5.0)** installed:
   - [Download Terraform](https://developer.hashicorp.com/terraform/install)
3. **An active AWS Account** with permissions to manage VPCs, Subnets, Security Groups, and EC2 instances.

---

## Quickstart Runbook

### Step 1: Clone and Inspect
```bash
git clone https://github.com/cherry-achyuth/AWS-Cloud-Infrastructure-Network-Architecture.git
cd AWS-Cloud-Infrastructure-Network-Architecture
```

### Step 2: Initialize Terraform
Downloads the HashiCorp AWS provider plugins:
```bash
terraform init
```

### Step 3: Validate Configuration
Checks formatting and validates syntax:
```bash
terraform fmt -check
terraform validate
```

### Step 4: Review Execution Plan (Zero Cost Default)
Inspects the resources Terraform will create without modifying AWS:
```bash
terraform plan
```
*Note: With `enable_ec2_instance = false`, only zero-cost networking and security resources are planned.*

### Step 5: (Optional) Test Compute Instance
To test the web server, create a `terraform.tfvars` file:
```hcl
enable_ec2_instance = true
admin_ssh_cidr      = "YOUR_PUBLIC_IP/32"  # (Optional: e.g. "203.0.113.50/32")
```
Then run:
```bash
terraform plan
```

### Step 6: Deploy Infrastructure (Requires Approval)
```bash
terraform apply
```

### Step 7: Clean Up All Resources
Always destroy resources when finished to maintain a clean account and guarantee zero cost:
```bash
terraform destroy
```

---

## Cost Considerations

| Resource | Quantity | Billing Behavior | Estimated Monthly Cost |
| :--- | :---: | :--- | :--- |
| **VPC, Subnets, Route Tables** | 1 VPC, 4 Subnets, 2 RTs | No charge in AWS. | **$0.00** |
| **Internet Gateway (IGW)** | 1 | No hourly charge. | **$0.00** |
| **Security Groups** | 2 | No charge. | **$0.00** |
| **Demo EC2 (`t2.micro`)** | 1 (Optional, disabled by default) | Free Tier covers 750 hrs/month for 12 months. Non-Free Tier: ~$0.0104/hr. | **$0.00** (Free Tier) or ~$7.50/mo |
| **Public IPv4 Address** | 1 (Only when EC2 is active) | Free Tier includes 750 hrs/month for EC2. Non-Free Tier: $0.005/hr. | **$0.00** (Free Tier) or ~$3.65/mo |
| **EBS Storage (8 GB gp3)** | 1 (Only when EC2 is active) | Free Tier includes 30 GB/month. Non-Free Tier: ~$0.08/GB-month. | **$0.00** (Free Tier) or ~$0.64/mo |
| **NAT Gateway** | 0 (Omitted by design) | Avoids ~$32.40/month idle charge per NAT GW. | **$0.00** (Design choice) |

---

## Future Enhancements

1. **VPC Flow Logs**: Stream network traffic logs to Amazon CloudWatch or S3 for security auditing and anomaly detection.
2. **AWS NAT Gateway**: Provision a managed NAT Gateway in Public Subnet 1 to enable outbound internet access for private workloads.
3. **Application Load Balancer (ALB)**: Deploy an internet-facing ALB spanning both public subnets to distribute traffic across redundant backend instances.
4. **AWS Systems Manager (SSM) Session Manager**: Eliminate the need for port 22 SSH keys entirely by connecting to instances via IAM and the SSM Agent.

Detailed implementation patterns for these enhancements are documented in [docs/learning-notes.md](docs/learning-notes.md).

---

## Troubleshooting Guide

A brief overview of common troubleshooting scenarios. For full diagnostic workflows, refer to [docs/learning-notes.md](docs/learning-notes.md).

- **EC2 Web Page Not Loading (`ERR_CONNECTION_TIMED_OUT`)**:
  - Verify `enable_ec2_instance = true`.
  - Check that the instance is in a public subnet associated with the public route table (`0.0.0.0/0 -> igw-xxxx`).
  - Verify Security Group allows inbound port 80.
- **SSH Connection Refused vs. Timed Out**:
  - *Timed Out*: Security group or route table is dropping packets. Verify `admin_ssh_cidr` matches your current public IP.
  - *Connection Refused*: Security group allowed the packet, but the `sshd` process is stopped on the instance.
- **Terraform Validation Errors**:
  - Ensure variable CIDRs are valid IPv4 blocks.
  - Ensure `admin_ssh_cidr` is not `0.0.0.0/0`.

---

## Author & Acknowledgements

Created as a practical AWS infrastructure and network automation project for cloud engineering demonstration and technical interview readiness.
