output "user_name" {
  value = aws_iam_user.user.name
}

output "user_unique_id" {
  value = aws_iam_user.user.unique_id
}

output "user_arn" {
  value = aws_iam_user.user.arn
}
