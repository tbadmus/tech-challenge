provider "aws" {
  region = var.region
}

# Reads the infrastructure root's state. One-directional: infrastructure knows
# nothing about this module, so it can still be planned and applied on its own.
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = var.infra_state_key
    region = var.region
  }
}

locals {
  infra = data.terraform_remote_state.infra.outputs

  cluster_name     = local.infra.cluster_name
  cluster_endpoint = local.infra.cluster_endpoint
  cluster_ca       = local.infra.cluster_certificate_authority_data
  region           = local.infra.region

  # Read from the infrastructure root rather than restated in a second tfvars
  # file. Two files that must agree are one file too many -- and the hosted zone
  # id in particular differs in every account, so duplicating it is exactly what
  # makes a repository non-portable.
  dns_enabled    = local.infra.dns_enabled
  domain_name    = local.infra.domain_name
  hosted_zone_id = local.infra.hosted_zone_id
}

# exec rather than a stored token: EKS tokens last 15 minutes, so a stored one
# would already be expired by the next apply.
provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region]
    }
  }
}
