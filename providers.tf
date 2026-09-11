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

# NOTE: the kubernetes and helm providers deliberately do NOT live here. They
# authenticate against the cluster API, so `terraform plan` would need network
# reach to an endpoint ADR-0004 restricts by CIDR -- which a GitHub-hosted
# runner does not have. Everything cluster-facing lives in cluster-addons/.
