# Pinned to provider v5 on purpose. These modules were written in 2022 and have
# NOT been migrated or tested against v6 -- see optional/tgw/README.md. Stating
# that honestly is more useful than claiming a compatibility nobody verified.
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
