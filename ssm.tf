# ---------------------------------------------------------------------------
# SSM access host — ADR-0004
# ---------------------------------------------------------------------------
# Replaces two bastions, a shared account-wide key pair named "mvp", an
# unencrypted private key that bootstrap.sh wrote into the repo root, and an
# ingress rule allowing SSH from 0.0.0.0/0.
#
# This instance has no key pair, no public IP, no inbound security group rule
# of any kind, and sits in a private subnet. Access is entirely outbound: the
# SSM agent dials out to Systems Manager, and an operator's session is routed
# back down that connection. Every session is recorded in CloudTrail, which
# SSH never was.
#
# It is a jump point, not a workstation -- its job is to terminate an SSM
# port-forward so kubectl can reach a private API endpoint:
#
#   make tunnel ENV=dev     # then: kubectl --server https://127.0.0.1:8443

data "aws_ssm_parameter" "al2023" {
  # Resolved from the public SSM parameter rather than a hardcoded AMI ID. The
  # old ami/ami.json pinned ami-0cb4e786f15603b0d, which is region-locked by
  # definition and was the reason the README said to find-and-replace values
  # across every file when changing region.
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "ssm" {
  count = var.create_ssm_host ? 1 : 0

  ami           = data.aws_ssm_parameter.al2023.value
  instance_type = var.ssm_host_instance_type

  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.ssm[0].id]
  iam_instance_profile   = aws_iam_instance_profile.ssm[0].name

  # No key_name. There is no SSH path to enable.

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data_replace_on_change = true
  user_data                   = <<-EOT
    #!/bin/bash
    set -euo pipefail
    dnf install -y kubectl || curl -sSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v${var.cluster_version}.0/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl 2>/dev/null || true
  EOT

  tags = merge(local.common_tags, {
    Name = "${local.name}-ssm"
    Role = "ssm-access-host"
  })
}

# Egress only. There is deliberately no aws_vpc_security_group_ingress_rule
# resource anywhere in this file.
resource "aws_security_group" "ssm" {
  count = var.create_ssm_host ? 1 : 0

  name        = "${local.name}-ssm"
  description = "SSM access host: outbound only, no inbound rules"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name}-ssm" })
}

resource "aws_vpc_security_group_egress_rule" "ssm_https" {
  count = var.create_ssm_host ? 1 : 0

  security_group_id = aws_security_group.ssm[0].id
  description       = "HTTPS to Systems Manager, ECR, and the EKS API endpoint"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

module "ssm_role" {
  source = "./modules/iam/role"

  count = var.create_ssm_host ? 1 : 0

  role_name          = "${local.name}-ssm"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  # AmazonSSMManagedInstanceCore is the whole grant. The old bastion role had
  # the same policy and the AMI installed the agent, so this path was already
  # 90% built -- it simply sat unused beside an SSH key pair doing the same job
  # less safely.
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}

resource "aws_iam_instance_profile" "ssm" {
  count = var.create_ssm_host ? 1 : 0

  name = "${local.name}-ssm"
  role = module.ssm_role[0].role_name
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "EC2AssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Grant the access host cluster-admin so an operator who reaches it can run
# kubectl without a second credential hop.
resource "aws_eks_access_entry" "ssm_host" {
  count = var.create_ssm_host ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = module.ssm_role[0].role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "ssm_host" {
  count = var.create_ssm_host ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = module.ssm_role[0].role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.ssm_host]
}
