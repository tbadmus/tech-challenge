# Development environment. Optimised for cost and iteration speed.

environment = "dev"
region      = "us-east-1"

vpc_cidr           = "10.0.0.0/16"
az_count           = 3
single_nat_gateway = true # one NAT: ~$32/mo instead of ~$96/mo, at the cost of AZ redundancy

cluster_version                = "1.35"
cluster_endpoint_public_access = true

# Allowlist for the public API endpoint is deliberately NOT set here.
#
# This repository is public. Publishing "the one IP address permitted to reach
# the EKS API of account <id>" next to that account id is a targeting aid, not
# configuration. The value therefore lives in terraform.tfvars, which is
# gitignored:
#
#   cluster_endpoint_public_access_cidrs = ["<your-ip>/32"]
#
# Get it with: curl -s https://checkip.amazonaws.com
# Anything not on the list reaches the API over SSM instead: make tunnel ENV=dev
#
# Note the precedence: a -var-file on the command line beats terraform.tfvars,
# so this key must be ABSENT here rather than set to a placeholder.

# Extra IAM principals granted cluster-admin through EKS access entries.
#
# Left empty deliberately, and empty is a working default: when this list is
# empty the EKS module grants cluster-admin to whoever runs the apply, so a
# fresh account is never left with a cluster nobody can reach. Add teammates'
# SSO permission-set role ARNs here when more than one person needs access.
#
# Role ARNs are account-specific, so hardcoding one makes the repo undeployable
# anywhere else -- find yours with:
#   aws iam list-roles --query "Roles[?contains(RoleName,'AWSReservedSSO')].Arn"
cluster_admin_role_arns = []

node_instance_type = "t3.medium" # 17 pods/node; ~$60/mo for two vs ~$121 for t3.large
node_min_size      = 2
node_max_size      = 4
node_desired_size  = 2

ecr_repository_name = "hello-world"

# ---------------------------------------------------------------------------
# Public DNS and TLS — optional, off by default so the stack deploys into any
# account with no prerequisites.
#
# This stack never registers a domain (ADR-0007). To enable, you need a domain
# that ALREADY resolves publicly, with a hosted zone in this account:
#
#   enable_dns    = true
#   domain_name   = "example.com"     # zone is looked up by name
#   app_subdomain = "hello"           # serves https://hello.example.com
#
# hosted_zone_id is only needed to disambiguate duplicate zone names.
# ---------------------------------------------------------------------------
enable_dns = false

tags = {
  CostCenter = "sandbox"
}
