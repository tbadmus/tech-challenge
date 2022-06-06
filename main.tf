module "ecr" {
  source    = "./modules/ecr"
  repo_name = "helloworld1"
}

module "network1" {
  source       = "./modules/vpc"
  cidr         = "10.0.0.0/16"
  cluster_name = local.cluster_name
}

module "network2" {
  source             = "./modules/vpc"
  cidr               = "172.31.0.0/16"
  is_public_required = false
  nat_gateway        = false
  cluster_name       = local.cluster_name
}

module "tgw" {
  source     = "./modules/tgw/gateway"
  tgw_name   = "mvp"
  depends_on = [module.network1, module.network2]
}

module "tgw-attachments" {
  source   = "./modules/tgw/attachment"
  for_each = { for attachment in local.vpc_attachments : attachment.name => attachment }

  subnet_ids = each.value.subnet_ids
  vpc_id     = each.value.vpc_id
  tgw_id     = module.tgw.id
  name       = each.value.name
  depends_on = [module.tgw]
}

module "tgw-routes" {
  source                 = "./modules/tgw/route"
  for_each               = { for route in local.tgw_routes : route.name => route }
  destination_cidr_block = each.value.destination_cidr_block
  route_table_id         = each.value.route_table_id
  tgw_id                 = module.tgw.id
  depends_on             = [module.tgw-attachments]
}

module "users" {
  source    = "./modules/iam/user"
  for_each  = toset(local.groups["bastion"].users)
  user_name = each.key
}

module "groups" {
  source   = "./modules/iam/group"
  for_each = local.groups

  group_name = each.value.name
  policies   = each.value.policies
  users      = each.value.users
  depends_on = [module.users]
}

module "eks2" {
  source          = "./modules/eks"
  name            = local.cluster_name
  node_group_name = "${local.cluster_name}-ng"
  subnet_ids      = module.network2.private_subnets
  role_name       = module.eksrole.role_name
  node_role_name  = module.noderole.role_name
  external_cidr   = [module.network1.vpc_cidr]
  depends_on = [
    module.noderole,
    module.eksrole,
    module.tgw-routes,
    null_resource.sp
  ]
}

resource "null_resource" "sp" {
  depends_on = [
    module.tgw-routes,
  ]
  triggers = {
    shell_hash = "${sha256(file("${path.module}/routes.sh"))}"
  }
  provisioner "local-exec" {
    command     = "bash routes.sh ${module.network1.vpc_id} ${module.tgw.id}"
    interpreter = ["/bin/bash", "-c"]
  }
}


module "bastionrole" {
  source                  = "./modules/iam/role"
  role_name               = "bastion-role"
  assume_role_policy      = data.aws_iam_policy_document.bastion-assume-role-policy.json
  managed_policy_arns     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  is_instance_profile_req = true
}

module "eksrole" {
  source              = "./modules/iam/role"
  role_name           = "cluster-role"
  assume_role_policy  = data.aws_iam_policy_document.eks-assume-role-policy.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy", "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"]
}

module "noderole" {
  source              = "./modules/iam/role"
  role_name           = "node-role"
  assume_role_policy  = data.aws_iam_policy_document.node-assume-role-policy.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy", "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly", "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"]
}

module "bastion" {
  source               = "./modules/ec2"
  name                 = "bastion"
  key_name             = "mvp"
  ami_id               = data.aws_ami.ubuntu.id
  subnet_id            = element(module.network1.public_subnets, 0)
  vpc_id               = module.network1.vpc_id
  iam_instance_profile = module.bastionrole.instance_profile
  bastion_ingress_rules = [{
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow-ssh"
    protocol    = "tcp"
  }]
}

resource "null_resource" "copy-files" {
  depends_on = [
    module.bastion
  ]

  connection {
    type        = "ssh"
    user        = local.username
    host        = module.bastion.public_ip
    private_key = file("${path.module}/techkey")
  }

  ## Copy files to VM :
  provisioner "file" {
    source      = "${path.module}/app/deployment.yaml"
    destination = "/home/${local.username}/deployment.yaml"
  }

  provisioner "file" {
    source      = "${path.module}/app/service.yaml"
    destination = "/home/${local.username}/service.yaml"
  }

  provisioner "file" {
    source      = "${path.module}/app/hello.js"
    destination = "/home/${local.username}/hello.js"
  }

  provisioner "file" {
    source      = "${path.module}/app/Dockerfile"
    destination = "/home/${local.username}/Dockerfile"
  }

  provisioner "file" {
    source      = "${path.module}/app/deploy.sh"
    destination = "/home/${local.username}/deploy.sh"
  }

  provisioner "file" {
    source      = "${path.module}/techkey"
    destination = "/home/${local.username}/techkey.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/${local.username}/deploy.sh",
      "chmod 400 /home/${local.username}/techkey.pem",
      "echo export REPO_URL=${module.ecr.url}>>/home/${local.username}/.bashrc"
    ]
  }
}

module "int-bastion" {
  source               = "./modules/ec2"
  name                 = "bastion"
  key_name             = "mvp"
  ami_id               = data.aws_ami.ubuntu.id
  subnet_id            = element(module.network2.private_subnets, 0)
  vpc_id               = module.network2.vpc_id
  iam_instance_profile = module.bastionrole.instance_profile
  bastion_ingress_rules = [{
    from_port   = 22
    to_port     = 22
    cidr_blocks = [module.network1.vpc_cidr]
    description = "allow-ssh"
    protocol    = "tcp"
  }]
}