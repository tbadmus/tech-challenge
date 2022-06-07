resource "aws_iam_user" "user" {
  name          = var.user_name
  force_destroy = true
}

resource "aws_iam_user_group_membership" "membership" {
  count  = length(var.groups) == 0 ? 0 : 1
  user   = aws_iam_user.user.name
  groups = var.groups
}
