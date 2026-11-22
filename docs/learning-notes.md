# AWS Cloud Networking & Infrastructure Operations: Learning Notes & Interview Guide

This guide bridges the gap between academic computer networking theory and practical AWS cloud infrastructure engineering. It is designed to prepare you to confidently demonstrate and defend this architecture in a technical interview for Cloud Engineer, Cloud Operations, or DevOps roles.

---

## Table of Contents
1. [Core Networking Primitives in AWS](#1-core-networking-primitives-in-aws)
   - [Virtual Private Cloud (VPC)](#virtual-private-cloud-vpc)
   - [Public vs. Private Subnets](#public-vs-private-subnets)
   - [Internet Gateway (IGW) & 1:1 NAT](#internet-gateway-igw--11-nat)
   - [Route Tables & Longest Prefix Match (LPM)](#route-tables--longest-prefix-match-lpm)
   - [Security Groups vs. Network Access Control Lists (NACLs)](#security-groups-vs-network-access-control-lists-nacls)
2. [End-to-End Packet Flow: Life of an HTTP Request](#2-end-to-end-packet-flow-life-of-an-http-request)
3. [Architectural Trade-offs: The NAT Gateway Cost Problem](#3-architectural-trade-offs-the-nat-gateway-cost-problem)
4. [Future Enhancement: VPC Flow Logs](#4-future-enhancement-vpc-flow-logs)
5. [Production Diagnostic Workflows & Troubleshooting](#5-production-diagnostic-workflows--troubleshooting)
   - [Scenario A: EC2 Instance is Unreachable over HTTP](#scenario-a-ec2-instance-is-unreachable-over-http)
   - [Scenario B: SSH Connection Timed Out vs. Connection Refused](#scenario-b-ssh-connection-timed-out-vs-connection-refused)
   - [Scenario C: EC2 Cannot Reach the Internet](#scenario-c-ec2-cannot-reach-the-internet)
   - [Scenario D: Subnet Associated with Wrong Route Table](#scenario-d-subnet-associated-with-wrong-route-table)
   - [Scenario E: DNS Resolution Failure](#scenario-e-dns-resolution-failure)
6. [Interview Defense Cheat Sheet](#6-interview-defense-cheat-sheet)

---

## 1. Core Networking Primitives in AWS

### Virtual Private Cloud (VPC)
- **Definition**: A logically isolated virtual network dedicated to your AWS account. It closely resembles a traditional physical data center network, but leverages AWS software-defined networking (SDN) built on the AWS Nitro system and VPC encapsulation protocols.
- **CIDR Block Selection**: When designing a VPC, we adhere to RFC 1918 private IPv4 ranges:
  - `10.0.0.0/8` (Largest space, standard in enterprise)
  - `172.16.0.0/12`
  - `192.168.0.0/16`
- **VPC Sizing (`10.0.0.0/16`)**:
  - The `/16` subnet mask provides $2^{32 - 16} = 65,536$ total IP addresses.
  - AWS VPC sizes can range from `/16` down to `/28` (16 IP addresses).
  - *Interview Tip*: Once a VPC CIDR is chosen, it cannot be edited, though secondary CIDRs can be attached. Never overlap CIDR blocks if you plan to connect networks using AWS Transit Gateway, Direct Connect, or VPC Peering.

---

### Public vs. Private Subnets
A subnet is a subdivision of a VPC's IP address range pinned to a specific **Availability Zone (AZ)** for fault isolation.

**What technically makes a subnet "Public"?**
In AWS, a subnet does not have an intrinsic "public" flag. A subnet is defined as *public* solely if both of the following conditions are met:
1. **Routing**: The subnet is associated with a route table that contains a default route (`0.0.0.0/0`) pointing to an **Internet Gateway (IGW)**.
2. **Addressing**: Instances launched inside the subnet have a public IPv4 or Elastic IP address (`map_public_ip_on_launch = true`).

If a subnet has no route to an IGW, it is a **Private Subnet**. Its IP addresses are completely unroutable from the public internet.

#### The 5 Reserved IP Addresses per Subnet
In every AWS subnet, AWS reserves the first 4 and the last 1 IP address (5 total):
For subnet `10.0.1.0/24` (256 addresses total, 251 usable):
- `10.0.1.0`: Network address.
- `10.0.1.1`: Reserved by AWS for the VPC router.
- `10.0.1.2`: Reserved by AWS for DNS (AmazonProvidedDNS, base of VPC + 2).
- `10.0.1.3`: Reserved by AWS for future use.
- `10.0.1.255`: Network broadcast address (AWS VPC does not support broadcast, but the address remains reserved).

---

### Internet Gateway (IGW) & 1:1 NAT
- **Architecture**: An Internet Gateway is not an EC2 instance, router box, or physical choke point. It is a horizontally scaled, redundant, and highly available software-defined component of the AWS network fabric.
- **How it works**:
  - EC2 instances in a VPC only ever know their private IP address (visible inside `ifconfig` or `ip addr`).
  - When an EC2 instance initiates traffic to the internet, the IGW intercepts packets at the VPC edge and performs **1:1 Static NAT**, swapping the private IP with the instance's assigned public IPv4 address.
  - Inbound internet packets destined for the public IP are translated by the IGW back to the private IP before arriving at the instance's Elastic Network Interface (ENI).
  - *Cost*: $0.00 base charge. You only pay for standard internet data transfer out.

---

### Route Tables & Longest Prefix Match (LPM)
A route table contains a set of rules (routes) that dictate where network traffic leaving a subnet is directed.

```text
Destination          Target
-------------------  ------------
10.0.0.0/16          local
0.0.0.0/0            igw-0abc1234
```

#### How AWS Evaluates Routes:
AWS always routes traffic using **Longest Prefix Match (LPM)**:
- Suppose an EC2 instance in Public Subnet 1 (`10.0.1.50`) sends a packet to an internal database in Private Subnet 1 (`10.0.11.20`).
- The packet destination is `10.0.11.20`.
- The router compares the destination against the table:
  - `10.0.0.0/16` (/16 prefix length: 16 matching bits)
  - `0.0.0.0/0` (/0 prefix length: 0 matching bits)
- Because `/16` is more specific (longer prefix) than `/0`, the packet matches `local` and is routed internally within the AWS VPC fabric. It *never* leaves the VPC or touches the Internet Gateway.

---

### Security Groups vs. Network Access Control Lists (NACLs)

| Feature | Security Group (SG) | Network Access Control List (NACL) |
| :--- | :--- | :--- |
| **Layer of Operation** | Elastic Network Interface (ENI) / Instance | Subnet boundary |
| **Statefulness** | **Stateful**: Return traffic is automatically tracked and allowed back. | **Stateless**: Inbound and outbound traffic must be explicitly permitted. |
| **Rule Processing** | Evaluates **all rules** before deciding to permit traffic. | Evaluates rules in strict **numerical order** (lowest number first). |
| **Action Types** | **ALLOW only** (implicit deny-all at end). | **ALLOW and DENY** rules supported. |
| **Default State** | Denies all inbound, allows all outbound. | Default VPC NACL allows all in/out. Custom NACLs deny all by default. |

#### Security Group Chaining (Defense-in-Depth)
Instead of opening database or backend ports to an IP range (e.g. `10.0.0.0/16`), we reference the **Security Group ID**:
```hcl
ingress {
  from_port       = 8080
  to_port         = 8080
  protocol        = "tcp"
  security_groups = [aws_security_group.web.id]
}
```
*Why this matters*: Only instances physically attached to `aws_security_group.web.id` can establish TCP connections on port 8080. If an attacker spins up an rogue EC2 instance inside the same VPC or private subnet, that rogue instance cannot communicate with the database because it lacks the trusted Web Security Group membership.

---

## 2. End-to-End Packet Flow: Life of an HTTP Request

When an external client visits `http://<EC2-Public-IP>`:

1. **DNS / Client Initiation**:
   - Client browser initiates a TCP SYN packet destined for `EC2-Public-IP:80`.
2. **Edge Ingress**:
   - The packet arrives at the AWS edge and reaches the **Internet Gateway (IGW)**.
3. **1:1 NAT Translation**:
   - The IGW translates the destination address from the public IP to the instance's private IP (`10.0.1.x`).
4. **Subnet Ingress (NACL)**:
   - The packet crosses the public subnet boundary. The Subnet NACL evaluates inbound rules (rule 100 allows TCP port 80).
5. **ENI Ingress (Security Group)**:
   - The packet reaches the instance's Elastic Network Interface (ENI). The Web Security Group checks if port 80 is allowed. It is permitted.
6. **Operating System Processing**:
   - The Linux kernel accepts the TCP handshake. The web server daemon (`httpd` / Apache) processes the HTTP GET request and generates the HTTP 200 response.
7. **Stateful Return Path**:
   - The web server sends the response packet from port 80 back to the client's high-order ephemeral port (e.g., 54321).
   - **Security Group Evaluation**: Because Security Groups are *stateful*, the response is automatically permitted without checking outbound rules.
   - **Route Table Lookup**: The destination IP is outside `10.0.0.0/16`, matching `0.0.0.0/0 -> igw-xxxx`.
   - **Subnet NACL Egress**: If using custom NACLs, an outbound rule allowing ephemeral ports (1024-65535) is evaluated.
   - **IGW Egress**: The IGW translates the source private IP back to the public IP and transmits the packet back to the client.

---

## 3. Architectural Trade-offs: The NAT Gateway Cost Problem

### The Enterprise Pattern vs. The Student Trap
In enterprise production setups, instances in private subnets (like database servers or backend microservices) often need to download Linux security patches or call third-party APIs. Because they have no public IP and no route to an IGW, AWS solves this with an **AWS NAT Gateway** placed in a public subnet.

### Why We Kept NAT Gateway Disabled by Default:
- **AWS NAT Gateway Pricing**:
  - ~$0.045 per hour per NAT Gateway ($32.40/month baseline).
  - In a Multi-AZ deployment (2 AZs = 2 NAT Gateways), that is **~$65/month** just sitting idle with 0 bytes transferred!
  - Plus $0.045 per GB of data processed.
- **The Senior Engineer Perspective**:
  "A good engineer builds what is required; a great engineer protects the company from wasteful spend." By keeping the private subnets strictly isolated by default, our infrastructure costs **$0.00** on Free Tier.

### How to Add a NAT Gateway in Production (Interview Talking Point):
If your production workload requires outbound internet from private subnets:
1. Allocate an AWS Elastic IP:
   ```hcl
   resource "aws_eip" "nat" {
     domain = "vpc"
   }
   ```
2. Provision the NAT Gateway inside a **Public Subnet**:
   ```hcl
   resource "aws_nat_gateway" "nat" {
     allocation_id = aws_eip.nat.id
     subnet_id     = aws_subnet.public[0].id
   }
   ```
3. Update the **Private Route Table** to direct `0.0.0.0/0` to the NAT Gateway:
   ```hcl
   resource "aws_route" "private_nat" {
     route_table_id         = aws_route_table.private.id
     destination_cidr_block = "0.0.0.0/0"
     nat_gateway_id         = aws_nat_gateway.nat.id
   }
   ```

---

## 4. Future Enhancement: VPC Flow Logs

### What are VPC Flow Logs?
VPC Flow Logs is an agentless network observability feature that captures information about the IP traffic going to and from network interfaces in your VPC.

### Why it is Essential for Cloud Operations:
- Security auditing and forensic analysis (detecting port scanning or unauthorized connections).
- Diagnosing overly restrictive or overly permissive security group rules.
- Network performance troubleshooting and traffic volume analysis.

### Standard Flow Log Record Format:
```text
<version> <account-id> <interface-id> <srcaddr> <dstaddr> <srcport> <dstport> <protocol> <packets> <bytes> <start> <end> <action> <log-status>
```
Example:
```text
2 123456789012 eni-0123456789abcdef0 203.0.113.50 10.0.1.15 54321 80 6 5 280 1672531199 1672531259 ACCEPT OK
2 123456789012 eni-0123456789abcdef0 198.51.100.2 10.0.1.15 44444 22 6 1 40 1672531199 1672531259 REJECT OK
```
- In line 1, TCP traffic (protocol 6) on port 80 was `ACCEPT`ed.
- In line 2, an unauthorized attempt on port 22 (SSH) was `REJECT`ed by the Security Group.

### How to Implement VPC Flow Logs in Terraform (Future Enhancement):
```hcl
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc-flow-logs/${local.name_prefix}"
  retention_in_days = 7
}

resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL" # ALL, ACCEPT, or REJECT
  vpc_id          = aws_vpc.main.id
}
```

---

## 5. Production Diagnostic Workflows & Troubleshooting

### Scenario A: EC2 Instance is Unreachable over HTTP
**Symptom**: Browser shows `ERR_CONNECTION_TIMED_OUT` when loading `http://<public-ip>`.

**Diagnostic Decision Tree**:
1. **Check Route Table**:
   - Does the subnet where the EC2 instance lives have a route to an Internet Gateway (`0.0.0.0/0 -> igw-xxxx`)?
   - If missing, packets cannot enter or leave the subnet.
2. **Check Public IP**:
   - Does the instance have an assigned public IPv4 address?
   - Command: `aws ec2 describe-instances --instance-ids <id> --query "Reservations[].Instances[].PublicIpAddress"`
3. **Check Security Group Ingress**:
   - Is port 80 allowed from `0.0.0.0/0`?
4. **Check Subnet Network ACL**:
   - Is inbound TCP port 80 allowed?
   - Is outbound ephemeral ports (1024-65535) allowed?
5. **Check Operating System / Web Server Daemon**:
   - Is the web server actually running?
   - SSH in (or use AWS Systems Manager Session Manager) and run:
     ```bash
     sudo systemctl status httpd
     sudo ss -tulpn | grep :80
     ```

---

### Scenario B: SSH Connection Timed Out vs. Connection Refused
Understanding this difference is a top interview question!

| Error Message | Root Cause Layer | What It Means |
| :--- | :--- | :--- |
| `ssh: connect to host ... port 22: Connection timed out` | **Network / Firewall Layer** (Security Group, NACL, or Route Table) | The SYN packet was silently dropped. The packet never reached the OS. Typically caused by your IP address not matching `admin_ssh_cidr`, or missing route table entry. |
| `ssh: connect to host ... port 22: Connection refused` | **Host / Operating System Layer** | The packet successfully reached the operating system, but no process was listening on port 22 (e.g. `sshd` is stopped), or a host firewall (like `iptables` or `nftables`) rejected it with a TCP RST. |
| `Permission denied (publickey)` | **Authentication / SSH Key Layer** | Network and daemon are healthy, but you supplied the wrong `.pem` private key, wrong username (e.g., used `root` or `ubuntu` instead of `ec2-user`), or file permissions on `~/.ssh/id_rsa` are too open (must be `chmod 400 key.pem`). |

---

### Scenario C: EC2 Cannot Reach the Internet
**Symptom**: `dnf update` or `ping 8.8.8.8` fails from inside the EC2 instance.

**Diagnostics**:
1. Check Security Group Egress:
   - Does the SG allow outbound traffic (`0.0.0.0/0` protocol `-1`)?
2. Check Route Table Association:
   - Verify the instance is in a Public Subnet explicitly associated with the Public Route Table.
3. Check ICMP Rules:
   - Note: `ping` uses ICMP, not TCP. If Security Group only allows TCP/UDP, `ping` will fail even if web traffic works!

---

### Scenario D: Subnet Associated with Wrong Route Table
**Symptom**: Resources in Public Subnet 2 cannot reach the internet despite having public IPs.

**Root Cause**:
- In AWS, if a subnet is not explicitly associated with a route table, it falls back to the **VPC Main Route Table**.
- If the Main Route Table has no route to the IGW, the subnet becomes effectively private!
- **Terraform Fix**: Always use explicit `aws_route_table_association` resources for every subnet:
  ```hcl
  resource "aws_route_table_association" "public" {
    count          = length(aws_subnet.public)
    subnet_id      = aws_subnet.public[count.index].id
    route_table_id = aws_route_table.public.id
  }
  ```

---

### Scenario E: DNS Resolution Failure
**Symptom**: `curl http://example.com` returns `Could not resolve host: example.com`.

**Root Cause**:
- If `enable_dns_support` is set to `false` on `aws_vpc`, the AmazonProvidedDNS server (`10.0.0.2`) will not respond to DNS queries.
- If `/etc/resolv.conf` is misconfigured on the instance.
- **Verification**: Run `nslookup amazon.com 10.0.0.2` or `dig amazon.com`.

---

## 6. Interview Defense Cheat Sheet

| Interviewer Question | Recommended Senior Response |
| :--- | :--- |
| *"Why did you create two public and two private subnets across two AZs?"* | *"To establish a highly available, multi-AZ foundation compliant with the AWS Well-Architected Framework. Distributing workloads across AZs protects against data center failure and allows seamless deployment of Application Load Balancers, which require at least two subnets in distinct AZs."* |
| *"Why did you avoid deploying a NAT Gateway in this project?"* | *"Cost governance. An active NAT Gateway incurs ~\$32.40/month even with zero traffic. For a baseline demonstration and learning environment, omitting the NAT Gateway eliminates unnecessary charges while maintaining strict private tier isolation. I have documented how to inject it when production workloads require outbound access."* |
| *"Why not open SSH to 0.0.0.0/0 for convenience?"* | *"Opening port 22 to 0.0.0.0/0 invites continuous automated brute-force attacks and bot scanning. We enforce least privilege by requiring a specific administrative CIDR (`admin_ssh_cidr`), leaving SSH disabled by default, and recommending AWS Systems Manager (SSM) Session Manager for keyless, secure access."* |
| *"Why use Security Group referencing instead of CIDR rules for private tier ingress?"* | *"IP addresses inside dynamic environments can change or expand. Referencing the Web Security Group ID creates an identity-based boundary. Only instances carrying that specific Security Group can communicate with the private tier, preventing unauthorized lateral movement within the VPC."* |
| *"How did you prevent accidental costs with the EC2 instance?"* | *"We decoupled compute from networking using a feature flag (`enable_ec2_instance = false`). Terraform's conditional resource creation ensures the VPC networking layer can be tested and validated without running billable compute instances."* |
