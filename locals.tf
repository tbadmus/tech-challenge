locals {
  # Every resource name in the stack derives from this, so a second
  # environment is a tfvars file rather than a find-and-replace.
  name = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "tbadmus/tech-challenge"
    },
    var.tags,
  )

  cluster_name    = "${local.name}-cluster"
  cluster_version = var.cluster_version
}
