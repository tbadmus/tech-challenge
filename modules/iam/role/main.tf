resource "aws_iam_role" "role" {
  name                = var.role_name
  managed_policy_arns = var.managed_policy_arns
  assume_role_policy  = var.assume_role_policy
  dynamic "inline_policy" {
    for_each = var.inline_policies

    content {
      name   = inline_policy.key
      policy = inline_policy.value
    }
  }
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_iam_instance_profile" "profile" {
  count = var.is_instance_profile_req ? 1 : 0
  name  = var.role_name
  role  = aws_iam_role.role.name
}
