locals {
  # Every resource name in the stack derives from this, so a second
  # environment is a tfvars file rather than a find-and-replace.
  name = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      # The repository name now lives in bootstrap/ with the CI identity, so
      # the infrastructure root no longer needs to know it.
      ManagedIn = "terraform"
    },
    var.tags,
  )

  cluster_name = "${local.name}-cluster"
}
