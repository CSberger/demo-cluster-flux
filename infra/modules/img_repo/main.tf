provider "aws" {
  region = var.aws_region
}

provider "github" {
  token        = var.github_token
  owner = var.github_owner
}

data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "main" {
  name                 = var.repo_name
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
# }

resource "aws_iam_user" "cicd_pusher" {
  name = "cicd_pusher_${var.repo_name}"
  path = "/"
}

resource "aws_iam_access_key" "cicd_pusher" {
  user = aws_iam_user.cicd_pusher.name
}

data "aws_iam_policy_document" "cicd_pusher" {
    statement {
        effect = "Allow"
        actions = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:GetRepositoryPolicy",
            "ecr:DescribeRepositories",
            "ecr:ListImages",
            "ecr:DescribeImages",
            "ecr:BatchGetImage",
            "ecr:GetLifecyclePolicy",
            "ecr:GetLifecyclePolicyPreview",
            "ecr:ListTagsForResource",
            "ecr:DescribeImageScanFindings",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
            "ecr:PutImage",
        ]
        resources = [resource.aws_ecr_repository.main.arn]
    }
    statement {
        effect = "Allow"
        actions = [
            "ecr:GetAuthorizationToken"
        ]
        resources = ["*"]
    }
}

resource "aws_iam_user_policy" "cicd_pusher" {
  name   = "cicd_pusher_${var.repo_name}"
  user   = aws_iam_user.cicd_pusher.name
  policy = data.aws_iam_policy_document.cicd_pusher.json
}


resource "github_actions_secret" "aws_creds_access" {
  repository       = var.repo_name
  secret_name      = "aws_access_key_id"
  plaintext_value  = resource.aws_iam_access_key.cicd_pusher.id
}

resource "github_actions_secret" "aws_creds_secret" {
  repository       = var.repo_name
  secret_name      = "aws_secret_access_key"
  encrypted_value  = resource.aws_iam_access_key.cicd_pusher.secret
}

resource "github_actions_variable" "aws_region" {
  repository       = var.repo_name
  variable_name    = "aws_region"
  value            = var.aws_region
}
