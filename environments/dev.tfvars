# Development environment. Optimised for cost and iteration speed.

environment = "dev"
region      = "us-east-1"

vpc_cidr           = "10.0.0.0/16"
az_count           = 3
single_nat_gateway = true # one NAT: ~$32/mo instead of ~$96/mo, at the cost of AZ redundancy

cluster_version                = "1.34"
cluster_endpoint_public_access = true

# Allowlist for the public API endpoint. Replace with your egress IP(s):
#   curl -s https://checkip.amazonaws.com
# Anything not on this list reaches the API over SSM port-forward instead.
cluster_endpoint_public_access_cidrs = []

# SSO permission-set role granted cluster-admin via an EKS access entry.
cluster_admin_role_arns = [
  "arn:aws:iam::841845498000:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AWSAdministratorAccess_f3fad16cc8305bb1",
]

node_instance_type = "t3.large"
node_min_size      = 2
node_max_size      = 4
node_desired_size  = 2

ecr_repository_name = "hello-world"

tags = {
  CostCenter = "sandbox"
  Owner      = "larry.badmus"
}
