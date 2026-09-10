output "region" {
  description = "Region this stack is deployed in."
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnets. EKS nodes and pods live here."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnets. Internet-facing load balancers and NAT gateways live here."
  value       = module.vpc.public_subnets
}

output "availability_zones" {
  description = "Availability zones in use."
  value       = local.azs
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateways. This is the egress address the cluster presents to the internet -- allowlist it upstream when a third party needs to know where traffic comes from."
  value       = module.vpc.nat_public_ips
}

output "cluster_name" {
  description = "Planned EKS cluster name. The cluster itself arrives in Phase 2."
  value       = local.cluster_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for the demo application image."
  value       = module.ecr.url
}
