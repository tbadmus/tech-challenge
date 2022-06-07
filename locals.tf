locals {

  cluster_name    = "mvp-cluster"
  cluster_version = "1.21"
  username        = "ubuntu"
  vpc_attachments = [
    {
      name       = "external"
      subnet_ids = module.network1.private_subnets
      vpc_id     = module.network1.vpc_id
    },
    {
      name       = "internal"
      subnet_ids = module.network2.private_subnets
      vpc_id     = module.network2.vpc_id
    },
  ]
  tgw_routes = [
    {
      name                   = "internet-to-internet-route"
      route_table_id         = module.network2.private_route_table_id
      destination_cidr_block = "0.0.0.0/0"
    },
    {
      name                   = "external-internal-route-1"
      route_table_id         = module.network1.public_route_table_id
      destination_cidr_block = "172.31.0.0/16"
    },
    {
      name                   = "external-internal-route-2"
      route_table_id         = module.network1.private_route_table_id
      destination_cidr_block = "172.31.0.0/16"
    }
  ]
  groups = {
    "bastion" = {
      "name" = "bastion-access"
      "policies" = {
        "bastion-access-group-policy" = data.aws_iam_policy_document.bastion-policy.json
      }
      "users" = ["larry.o.badmus"]
    }
  }
}