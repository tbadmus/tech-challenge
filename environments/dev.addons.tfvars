# Inputs for the cluster-addons root module (dev).
#   cd cluster-addons
#   terraform init -backend-config=../environments/dev.s3.tfbackend \
#                  -backend-config="key=dev/cluster-addons.tfstate"
#   terraform apply -var-file=../environments/dev.addons.tfvars

region          = "us-east-1"
state_bucket    = "tech-challenge-tfstate-841845498000"
infra_state_key = "dev/terraform.tfstate"

enable_dns     = true
domain_name    = "elbeetest.com"
hosted_zone_id = "Z06069972H7T90FAW0B2Q"

lb_controller_chart_version = "3.5.0"
external_dns_chart_version  = "1.19.0"
