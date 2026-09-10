# Production shape. Not deployed during the tech challenge -- it exists so the
# dev/prod difference is visible as configuration rather than as forked code.

environment = "prod"
region      = "us-east-1"

vpc_cidr           = "10.1.0.0/16"
az_count           = 3
single_nat_gateway = false # one NAT per AZ: no shared failure domain, no cross-AZ egress charges

cluster_version                = "1.35"
cluster_endpoint_public_access = false # private endpoint only; reach it over SSM or an in-VPC runner

# Mandatory, not optional, when the endpoint is private: without these, image
# pulls, log shipping and SSM sessions all fail. ~$150-200/mo across 3 AZs.
enable_interface_endpoints = true

cluster_admin_role_arns = []

node_instance_type = "m6i.large"
node_min_size      = 3
node_max_size      = 9
node_desired_size  = 3

ecr_repository_name = "hello-world"

tags = {
  CostCenter = "platform"
}
