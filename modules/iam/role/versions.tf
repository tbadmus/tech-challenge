# Every module declares what it was written against. Without this a consumer
# can wire the module into a root running any provider version and only find
# out at apply time -- which is how the pre-modernization code ended up unable
# to `terraform init` at all once provider v6 removed three of its arguments.
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
