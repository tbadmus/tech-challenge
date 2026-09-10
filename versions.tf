# Provider and Terraform version constraints.
#
# Both are pinned deliberately. The pre-modernization code left the AWS
# provider unconstrained, which meant every `terraform init` resolved to
# whatever was newest -- and provider v6 removed three constructs the old
# modules relied on. Pinning plus a committed .terraform.lock.hcl is what
# makes a run on a laptop and a run in CI resolve identically.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
