# ---------------------------------------------------------------------------
# Network — single VPC, ADR-0001
# ---------------------------------------------------------------------------
# Replaces the two-VPC + Transit Gateway topology. Containment comes from
# subnet routing, not from a VPC boundary: nodes in a private subnet have no
# public IP and no inbound path, and that is true whether or not those subnets
# live in their own VPC.
#
# Uses terraform-aws-modules/vpc/aws per ADR-0002. The subnet tags below are
# not decoration -- the AWS Load Balancer Controller discovers where it may
# place load balancers by reading them, so an ALB lands in a public subnet and
# an internal NLB in a private one without either being named anywhere.

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Deliberate, documented address plan. The module this replaces derived
  # subnets with cidrsubnet(cidr, 5, i + 1) and cidrsubnet(cidr, 5, i + 12) --
  # magic offsets with no comment, which is how you end up afraid to change a
  # network.
  #
  # For a /16:
  #   private  10.0.0.0/19,  10.0.32.0/19,  10.0.64.0/19   (8190 usable each)
  #   public   10.0.240.0/24, 10.0.241.0/24, 10.0.242.0/24 (254 usable each)
  #   free     10.0.96.0 - 10.0.239.255, reserved for future tiers
  #
  # Private subnets are large because the VPC CNI assigns every pod an address
  # from them; a /24 there runs out of pods long before it runs out of nodes.
  # Public subnets only ever hold load balancer ENIs and NAT gateways.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 3, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 240 + i)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # Required for EKS: nodes resolve the cluster endpoint by DNS name, and
  # private hosted zones for interface endpoints do not resolve without both.
  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # Flow logs to CloudWatch. The old stack had no network visibility at all,
  # which makes "why can this pod not reach that" unanswerable.
  enable_flow_log                                 = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_logs
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    Tier                     = "public"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    Tier                              = "private"
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# VPC endpoints
# ---------------------------------------------------------------------------
# Two different things, deliberately controlled separately.
#
# The S3 gateway endpoint is FREE and always on. ECR stores image layers in
# S3, so without it every image pull is billed twice: once as NAT data
# processing ($0.045/GB) and once as egress. Turning it on is pure saving.
#
# Interface endpoints cost roughly $0.01 per hour per AZ each. The set below
# across three AZs is on the order of $150-200/month -- real money for a
# sandbox. In dev, where a NAT gateway exists, they are optional. In prod,
# where ADR-0004 sets the API endpoint fully private, they are mandatory:
# without them image pulls and log shipping fail with no obvious cause.

module "vpc_endpoints_gateway" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat(module.vpc.private_route_table_ids, module.vpc.public_route_table_ids)
      tags            = { Name = "${local.name}-s3-gateway" }
    }
  }

  tags = local.common_tags
}

module "vpc_endpoints_interface" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  count = var.enable_interface_endpoints ? 1 : 0

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints[0].id]

  endpoints = {
    # Container image pulls.
    ecr_api = { service = "ecr.api", private_dns_enabled = true }
    ecr_dkr = { service = "ecr.dkr", private_dns_enabled = true }

    # Log shipping and metrics.
    logs       = { service = "logs", private_dns_enabled = true }
    monitoring = { service = "monitoring", private_dns_enabled = true }

    # IAM role assumption for Pod Identity / IRSA.
    sts = { service = "sts", private_dns_enabled = true }

    # SSM Session Manager needs all three of these to establish a session.
    # This is the path ADR-0004 uses to reach a private API endpoint without
    # SSH, so on a private cluster they are load-bearing, not optional.
    ssm         = { service = "ssm", private_dns_enabled = true }
    ssmmessages = { service = "ssmmessages", private_dns_enabled = true }
    ec2messages = { service = "ec2messages", private_dns_enabled = true }

    # Node lifecycle and load balancer management from in-cluster controllers.
    ec2                  = { service = "ec2", private_dns_enabled = true }
    elasticloadbalancing = { service = "elasticloadbalancing", private_dns_enabled = true }
    autoscaling          = { service = "autoscaling", private_dns_enabled = true }
  }

  tags = local.common_tags
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name        = "${local.name}-vpc-endpoints"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name}-vpc-endpoints" })
}

# Only 443, only from inside the VPC. The rule this replaces opened all 65,535
# TCP ports to an entire peer VPC CIDR.
resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from within the VPC"
  cidr_ipv4         = module.vpc.vpc_cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
