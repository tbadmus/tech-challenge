# Root module.
#
# Network lives in network.tf. The EKS cluster arrives in Phase 2, ingress in
# Phase 3. Until then this file holds only the application registry.
#
# What used to be here -- two VPC modules, a Transit Gateway with three route
# modules, a null_resource wrapping routes.sh, an EKS module reached through
# a five-entry depends_on chain, two bastions and a pair of IAM user/group
# modules -- is removed by ADR-0001 and ADR-0004. The Transit Gateway modules
# are preserved under optional/tgw/ as a standalone lesson.

module "ecr" {
  source = "./modules/ecr"

  repo_name             = var.ecr_repository_name
  image_retention_count = var.ecr_image_retention_count

  # Sandbox convenience: lets `terraform destroy` remove the repository without
  # emptying it by hand first. Never true outside dev.
  force_delete = var.environment == "dev"
}
