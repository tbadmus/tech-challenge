resource "aws_ecr_repository" "main" {
  name = var.repo_name

  image_scanning_configuration {
    scan_on_push = false
  }
}
