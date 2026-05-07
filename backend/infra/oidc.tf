data "aws_caller_identity" "current" {}

# GitHub Actions OIDC provider — one per AWS account.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Trust policy for the staging deploy role. Locked to:
#   repo:<owner>/<repo>:ref:refs/heads/master      (push-to-master deploys)
#   repo:<owner>/<repo>:pull_request               (CI pipeline reads, not deploys)
#   repo:<owner>/<repo>:environment:staging        (deploy-staging.yml job uses
#                                                   `environment: staging`, which
#                                                   makes GitHub OIDC override the
#                                                   sub claim to this value)
data "aws_iam_policy_document" "gha_staging_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.gha_repo_full_name}:ref:refs/heads/master",
        "repo:${var.gha_repo_full_name}:pull_request",
        "repo:${var.gha_repo_full_name}:environment:staging",
      ]
    }
  }
}

resource "aws_iam_role" "gha_staging" {
  name               = "${local.name_prefix}-gha-deploy"
  assume_role_policy = data.aws_iam_policy_document.gha_staging_assume_role.json
  description        = "Assumed by GitHub Actions on push-to-master and PR; deploys staging."
}

# Deploy permissions: scope each statement to the resources we touch.
data "aws_iam_policy_document" "gha_staging_deploy" {
  # ECR: push the new image
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:ListImages",
    ]
    resources = [aws_ecr_repository.backend.arn]
  }

  # ECS: roll the service + run migrations as a one-shot task
  statement {
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "ecs:RunTask",
      "ecs:StopTask",
    ]
    resources = ["*"]
  }
  # ECS RunTask must be allowed to PassRole the existing task + execution roles
  statement {
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_task.arn,
      aws_iam_role.ecs_execution.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # CloudWatch Logs: tail the migration task's logs from the workflow
  statement {
    actions = [
      "logs:GetLogEvents",
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.backend.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "gha_staging_deploy" {
  name   = "${local.name_prefix}-gha-deploy"
  role   = aws_iam_role.gha_staging.id
  policy = data.aws_iam_policy_document.gha_staging_deploy.json
}

data "aws_iam_policy_document" "gha_production_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      # GitHub injects this exact value when the workflow targets the
      # "production" Environment defined in repo Settings → Environments.
      values = ["repo:${var.gha_repo_full_name}:environment:production"]
    }
  }
}

resource "aws_iam_role" "gha_production" {
  name               = "${local.name_prefix}-gha-production-deploy"
  assume_role_policy = data.aws_iam_policy_document.gha_production_assume_role.json
  description        = "Assumed by GitHub Actions production-deploy workflow only after the production Environment approval gate."
}

# Production deploy policy. Wildcards on ECR and ECS allow promoting images
# to a future production ECR repo and rolling production ECS resources that
# Plan 8c will create in a separate Terraform state.
data "aws_iam_policy_document" "gha_production_deploy" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:ListImages",
    ]
    # Wildcard so the role can push to both staging and (future) production ECR repos.
    resources = ["arn:aws:ecr:*:${data.aws_caller_identity.current.account_id}:repository/${var.project}-*"]
  }
  statement {
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "ecs:RunTask",
      "ecs:StopTask",
    ]
    resources = ["*"]
  }
  statement {
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_task.arn,
      aws_iam_role.ecs_execution.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "gha_production_deploy" {
  name   = "${local.name_prefix}-gha-production-deploy"
  role   = aws_iam_role.gha_production.id
  policy = data.aws_iam_policy_document.gha_production_deploy.json
}
