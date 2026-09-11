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

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version actually running."
  value       = module.eks.cluster_version
}

output "cluster_endpoint_public_access" {
  description = "Whether the API endpoint is reachable from outside the VPC. The pre-modernization stack left this at the AWS default of true with 0.0.0.0/0."
  value       = var.cluster_endpoint_public_access
}

output "cluster_security_group_id" {
  description = "Security group the control plane uses to talk to nodes."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN, for IRSA where Pod Identity is not an option."
  value       = module.eks.oidc_provider_arn
}

output "node_group_role_arn" {
  description = "IAM role the managed node group runs as."
  value       = try(module.eks.eks_managed_node_groups["default"].iam_role_arn, null)
}

output "ssm_host_instance_id" {
  description = "Instance ID to target with `aws ssm start-session`. Empty when create_ssm_host is false."
  value       = try(aws_instance.ssm[0].id, "")
}

output "kubeconfig_command" {
  description = "Command to point kubectl at this cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "tunnel_command" {
  description = "SSM port-forward to the API endpoint, for when the public endpoint is disabled or your IP is not allowlisted."
  value = var.create_ssm_host ? join(" ", [
    "aws ssm start-session --target ${try(aws_instance.ssm[0].id, "")}",
    "--document-name AWS-StartPortForwardingSessionToRemoteHost",
    "--parameters '{\"host\":[\"${replace(module.eks.cluster_endpoint, "https://", "")}\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"8443\"]}'",
  ]) : ""
}

output "hosted_zone_id" {
  description = "Resolved Route53 zone ID, whether supplied directly or looked up by name. Consumed by the cluster-addons root module."
  value       = local.zone_id
}

output "domain_name" {
  description = "Apex domain in use. Empty when enable_dns is false."
  value       = var.domain_name
}

output "dns_enabled" {
  description = "Whether DNS and TLS are enabled, so cluster-addons does not need its own copy of the flag."
  value       = var.enable_dns
}

output "app_fqdn" {
  description = "Public hostname of the demo app. Empty until enable_dns is set with a resolvable domain."
  value       = local.app_fqdn
}

output "app_certificate_arn" {
  description = "ACM certificate ARN for the app hostname."
  value       = try(aws_acm_certificate_validation.app[0].certificate_arn, "")
}



output "cluster_certificate_authority_data" {
  description = "Cluster CA, consumed by the cluster-addons root module."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "container_insights_log_groups" {
  description = "CloudWatch log groups Fluent Bit ships into."
  value       = [for g in aws_cloudwatch_log_group.container_insights : g.name]
}
