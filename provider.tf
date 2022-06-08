provider "aws" {
  region  = "us-west-2"
  default_tags {
    tags = {
      Environment = "MVP"
    }
  }
}

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # version = ">= 3.68"
    }
  }
  backend "s3" {
    bucket = "mvp-tfstate-bkt"
    key    = "lb-terraform.tfstate"
    region = "us-west-2"
  }
}
