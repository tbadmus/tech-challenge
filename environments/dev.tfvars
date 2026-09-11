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

# Humans granted cluster-admin, through EKS access entries.
#
# DELIBERATELY ABSENT from this file, for the same two reasons as the CIDR
# allowlist above -- and the first one is a trap worth understanding.
#
# 1. PRECEDENCE. A -var-file on the command line beats both terraform.tfvars and
#    TF_VAR_ environment variables. Setting this key here to ANY value, even the
#    empty list, would therefore override what CI passes and silently revoke
#    every human's access on the next pipeline apply. Absent is the only safe
#    state; a placeholder is not.
#
# 2. Role ARNs carry the account id and the permission-set id. This repository
#    is public, and "the principal that administers the cluster in account <id>"
#    is a targeting aid rather than configuration.
#
# Set it in the two places that are not tracked:
#
#   terraform.tfvars               (gitignored, for local plan/apply)
#     cluster_admin_role_arns = ["arn:aws:iam::<id>:role/aws-reserved/sso.amazonaws.com/<role>"]
#
#   gh secret set TF_VAR_cluster_admin_role_arns   (for CI)
#     value: ["arn:aws:iam::<id>:role/aws-reserved/sso.amazonaws.com/<role>"]
#
# Find yours with:
#   aws iam list-roles --query "Roles[?contains(RoleName,'AWSReservedSSO')].Arn"
#
# Leaving it unset is a working default -- the apply principal is granted
# cluster-admin either way -- but "working" means CI can reach the cluster. YOU
# cannot. An AWS account with AdministratorAccess grants exactly zero Kubernetes
# RBAC: kubectl returns "the server has asked for the client to provide
# credentials", and the console Resources tab shows "Unauthorized".
#
# Do NOT list the role that runs the apply. The module already grants it, and a
# second entry for the same principal fails with ResourceInUseException.

node_instance_type = "t3.medium" # 17 pods/node; ~$60/mo for two vs ~$121 for t3.large
node_min_size      = 2
node_max_size      = 4
node_desired_size  = 2

ecr_repository_name = "hello-world"

# Shortest window AWS allows. A scheduled-for-deletion key still bills, and this
# environment is rebuilt often enough for 30 days of them to add up. See the
# variable description for why prod should not copy this.
kms_key_deletion_window_in_days = 7

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
enable_dns = true
domain_name = "elbeetest.com"
app_subdomain = "hello-world"

tags = {
  CostCenter = "sandbox"
}
