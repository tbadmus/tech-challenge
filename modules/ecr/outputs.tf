output "url" {
  value = aws_ecr_repository.main.repository_url
}

output "id" {
  value = aws_ecr_repository.main.registry_id
}
output "name" {
  value = aws_ecr_repository.main.name
}

output "arn" {
  value = aws_ecr_repository.main.arn
}
