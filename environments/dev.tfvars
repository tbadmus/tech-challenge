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

# SSO permission-set role granted cluster-admin via an EKS access entry.
cluster_admin_role_arns = [
  "arn:aws:iam::841845498000:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AWSAdministratorAccess_f3fad16cc8305bb1",
]

node_instance_type = "t3.medium" # 17 pods/node; ~$60/mo for two vs ~$121 for t3.large
node_min_size      = 2
node_max_size      = 4
node_desired_size  = 2

ecr_repository_name = "hello-world"

tags = {
  CostCenter = "sandbox"
  Owner      = "larry.badmus"
}
