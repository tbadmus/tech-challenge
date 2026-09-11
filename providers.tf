provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}


# NOTE: the kubernetes and helm providers deliberately do NOT live here. They
# authenticate against the cluster API, so `terraform plan` would need network
# reach to an endpoint ADR-0004 restricts by CIDR -- which a GitHub-hosted
# runner does not have. Everything cluster-facing lives in cluster-addons/.
