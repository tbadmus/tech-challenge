provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

# The Route53 Domains API lives only in us-east-1, regardless of where the rest
# of the stack is deployed. An alias keeps domain.tf correct if var.region ever
# moves, instead of silently depending on dev happening to be us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

# ---------------------------------------------------------------------------
# Cluster providers
# ---------------------------------------------------------------------------
# These authenticate against the cluster created in this same root module.
# Terraform cannot plan a provider's configuration from resources that do not
# exist yet, so on a completely fresh account the very first apply must create
# the cluster before these providers can be configured. In practice the EKS
# module's dependency graph handles it, but be aware of the shape:
#
#   - A `terraform destroy` that removes the cluster can leave these providers
#     unable to authenticate while Terraform still wants to delete the Helm
#     release and StorageClass. Destroy those first, or accept one
#     `-target`ed cleanup pass. `make destroy` handles this ordering.
#   - Splitting cluster software into its own root module avoids the problem
#     entirely and is the right call for a production estate. It is kept here
#     so the whole stack reads as one unit for teaching purposes.
#
# Auth uses `exec` rather than a stored token: tokens last 15 minutes, so a
# stored one would be expired by the next apply.

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

# Helm provider v3 takes `kubernetes` as an attribute rather than a block.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
