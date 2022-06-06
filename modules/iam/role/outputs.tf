output "role_arn" {
  value = aws_iam_role.role.arn
}

output "role_name" {
  value = aws_iam_role.role.name
}

output "instance_profile" {
  value = var.is_instance_profile_req ? aws_iam_instance_profile.profile[0].name : ""
}