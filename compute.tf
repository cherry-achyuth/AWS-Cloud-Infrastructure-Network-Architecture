# ==============================================================================
# Compute Infrastructure: Optional Demo EC2 Instance
# ==============================================================================
# Provisions an optional Linux EC2 instance in Public Subnet 1 to validate
# connectivity, DNS resolution, and HTTP ingress.
#
# Cost & Governance Safeguards:
# 1. Disabled by default (var.enable_ec2_instance = false).
# 2. Uses Free-Tier eligible instance type (t2.micro / t3.micro).
# 3. IMDSv2 (Instance Metadata Service v2) is strictly enforced for security.
# 4. No credentials or keys are hardcoded.

# ------------------------------------------------------------------------------
# 1. Dynamic AMI Lookup (Amazon Linux 2023)
# ------------------------------------------------------------------------------
# Retrieves the most recent official Amazon Linux 2023 AMI maintained by AWS.
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ------------------------------------------------------------------------------
# 2. Demo EC2 Instance (Conditional Provisioning)
# ------------------------------------------------------------------------------
resource "aws_instance" "demo_web" {
  count = var.enable_ec2_instance ? 1 : 0

  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.ec2_instance_type

  # Place instance into Public Subnet 1 (AZ 1)
  subnet_id = aws_subnet.public[0].id

  # Attach Public Web Security Group
  vpc_security_group_ids = [aws_security_group.web.id]

  # Optional SSH Key Pair (only attached if provided)
  key_name = var.ec2_key_name != "" ? var.ec2_key_name : null

  # Enforce IMDSv2 to prevent Server-Side Request Forgery (SSRF) metadata theft
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Root block device configuration
  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${local.name_prefix}-demo-web-root-vol"
    }
  }

  # User Data: Bootstraps a lightweight web server with IMDSv2 metadata
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd
              systemctl start httpd
              systemctl enable httpd

              # Query instance metadata securely using IMDSv2 session token
              TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
              INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
              AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
              LOCAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

              cat <<HTML > /var/www/html/index.html
              <!DOCTYPE html>
              <html>
              <head>
                  <title>AWS Cloud Infrastructure Demo</title>
                  <style>
                      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 40px; background-color: #f7f9fa; color: #232f3e; }
                      .card { background: white; border-radius: 8px; padding: 28px; box-shadow: 0 4px 12px rgba(0,0,0,0.08); max-width: 620px; margin: auto; border-top: 4px solid #ff9900; }
                      h1 { margin-top: 0; color: #232f3e; font-size: 24px; }
                      p.subtitle { color: #545b64; font-size: 15px; margin-bottom: 20px; }
                      .metric-box { background: #f1f3f3; padding: 12px 16px; border-radius: 6px; margin: 10px 0; font-size: 14px; }
                      .metric-label { font-weight: 600; color: #545b64; display: inline-block; width: 140px; }
                      .status-pill { display: inline-block; padding: 4px 10px; background-color: #1d8102; color: white; border-radius: 12px; font-size: 12px; font-weight: 600; }
                  </style>
              </head>
              <body>
                  <div class="card">
                      <h1>AWS Cloud Infrastructure & Network Architecture</h1>
                      <p class="subtitle">Operational demo instance deployed in a public subnet.</p>
                      <div class="metric-box"><span class="metric-label">Status:</span> <span class="status-pill">HEALTHY</span></div>
                      <div class="metric-box"><span class="metric-label">Instance ID:</span> $INSTANCE_ID</div>
                      <div class="metric-box"><span class="metric-label">Availability Zone:</span> $AZ</div>
                      <div class="metric-box"><span class="metric-label">Private IPv4:</span> $LOCAL_IP</div>
                  </div>
              </body>
              </html>
              HTML
              EOF

  tags = {
    Name = "${local.name_prefix}-demo-web"
  }
}
