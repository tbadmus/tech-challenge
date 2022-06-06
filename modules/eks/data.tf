data "aws_iam_role" "clusterrole" {
  name = var.role_name
}

data "aws_iam_role" "noderole" {
  name = var.node_role_name
}
