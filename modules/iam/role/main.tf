resource "aws_iam_role" "role" {
  name               = var.role_name
  assume_role_policy = var.assume_role_policy

  lifecycle {
    create_before_destroy = false
  }
}

# AWS provider v6 removed the `managed_policy_arns` argument and the inline
# `inline_policy` block from aws_iam_role. Both are now separate resources.
# The split is an improvement: attachments and policies become individually
# addressable in state instead of being an opaque list on the role.

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.role.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.role.id
  policy = each.value
}

resource "aws_iam_instance_profile" "profile" {
  count = var.is_instance_profile_req ? 1 : 0

  name = var.role_name
  role = aws_iam_role.role.name
}
