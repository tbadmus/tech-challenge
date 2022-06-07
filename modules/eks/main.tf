resource "aws_eks_cluster" "cluster" {
  name     = var.name
  role_arn = data.aws_iam_role.clusterrole.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    "Name" = var.name
  }
}

resource "aws_eks_node_group" "this" {
  # Required
  cluster_name  = aws_eks_cluster.cluster.name
  node_role_arn = data.aws_iam_role.noderole.arn
  subnet_ids    = var.subnet_ids

  scaling_config {
    min_size     = var.min_size
    max_size     = var.max_size
    desired_size = var.desired_size
  }

  node_group_name = var.node_group_name
  ami_type        = var.ami_type
  version         = var.cluster_version

  capacity_type  = var.capacity_type
  disk_size      = var.disk_size
  instance_types = var.instance_types

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size,
    ]
  }
  tags = {
    "Name" = var.node_group_name
  }
}

resource "aws_security_group_rule" "ec2" {
  security_group_id = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = var.external_cidr
}
