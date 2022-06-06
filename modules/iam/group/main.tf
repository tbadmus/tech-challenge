resource "aws_iam_group" "group" {
  name = var.group_name
  path = var.path
}

resource "aws_iam_group_policy" "policy" {
  for_each = var.policies
  name     = each.key
  group    = aws_iam_group.group.name
  policy   = each.value
}

resource "aws_iam_group_policy_attachment" "policy-attach" {
  for_each   = toset(var.managed_policies)
  group      = aws_iam_group.group.name
  policy_arn = each.key
}

resource "aws_iam_group_membership" "user-member" {
  count = length(var.users) == 0 ? 0 : 1
  name  = "${var.group_name}-group-membership"
  users = var.users

  group = aws_iam_group.group.name
}
