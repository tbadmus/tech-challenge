resource "aws_ecr_repository" "main" {
  name = var.repo_name

  # Tag immutability is what makes deploying by tag safe: once pushed, a tag
  # cannot be moved underneath a running Deployment. The original repo left
  # tags mutable AND pushed an implicit `:latest` on every build, so the
  # Deployment's pod spec never changed and new code never rolled out.
  image_tag_mutability = var.image_tag_mutability

  # Was explicitly disabled. Scanning on push is free at BASIC level.
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  # Allows `terraform destroy` to remove a repository that still holds images.
  # Appropriate for a demo environment that is torn down between sessions;
  # leave it false anywhere images matter.
  force_delete = var.force_delete

  tags = {
    Name = var.repo_name
  }
}

# Without this, images accumulate forever and bill forever. Untagged images are
# expired aggressively because they are almost always orphaned layers from a
# re-pushed tag.
resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent ${var.image_retention_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.image_retention_count
        }
        action = { type = "expire" }
      },
    ]
  })
}
