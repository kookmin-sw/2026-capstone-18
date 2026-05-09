resource "aws_ecr_repository" "ml_demo" {
  name                 = "${local.name_prefix}-ml-demo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # ephemeral: tear-down should not require manual image cleanup

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "ml_demo" {
  repository = aws_ecr_repository.ml_demo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
