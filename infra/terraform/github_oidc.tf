# GitHub Actions authenticates to AWS via OIDC federation — no long-lived AWS access
# keys stored as GitHub secrets. Two roles, matching the two trust levels the CI/CD
# pipelines actually need (docs/architecture.md §9):
#   - github_actions_deploy: narrow — push images, roll ECS services, sync the two SPA
#     buckets, invalidate CloudFront. Used by frontend/api/workers-ci-cd.yml.
#   - github_actions_terraform: broad — full infra changes. Used only by
#     infra-ci-cd.yml's apply job, which sits behind the "infra-prod" environment's
#     manual-approval gate (configured in GitHub repo settings, not here).
#
# Both roles trust only pushes to `main` in this specific repo — PRs never get AWS
# credentials (the workflows' build/test steps run without them regardless).
#
# IMPORTANT — these are account-wide, NOT per-environment: an IAM role name is unique
# per AWS account, not per Terraform workspace, so if every dev/staging/prod workspace
# tried to create "northbridge-github-actions-deploy" independently, the second apply
# would fail with "already exists". Everything in this file is gated behind
# create_shared_resources, which you set =true in exactly ONE workspace (pick whichever
# you'll treat as authoritative, e.g. prod) and leave at its default (false) everywhere else.

variable "create_shared_resources" {
  description = "Create the account-wide GitHub OIDC provider + deploy roles. Set true in exactly one workspace, ever — see the file header comment."
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "GitHub repo these OIDC roles trust, as \"owner/repo\" — e.g. \"jyo321/project-simulation\"."
  type        = string
  default     = ""
}

variable "github_oidc_provider_exists" {
  description = "Set true if your AWS account already has a GitHub Actions OIDC provider (only one can exist per account) — Terraform will reuse it instead of creating a duplicate."
  type        = bool
  default     = false
}

data "aws_iam_openid_connect_provider" "github_existing" {
  count = var.create_shared_resources && var.github_oidc_provider_exists ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_shared_resources && !var.github_oidc_provider_exists ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  github_oidc_provider_arn = var.create_shared_resources ? (
    var.github_oidc_provider_exists ? data.aws_iam_openid_connect_provider.github_existing[0].arn : aws_iam_openid_connect_provider.github[0].arn
  ) : null
  github_main_branch_sub = "repo:${var.github_repo}:ref:refs/heads/main"
}

data "aws_iam_policy_document" "github_trust" {
  count = var.create_shared_resources ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_main_branch_sub]
    }
  }
}

# ---------------------------------------------------------------------------
# Narrow deploy role — frontend / api / workers pipelines
# ---------------------------------------------------------------------------

resource "aws_iam_role" "github_actions_deploy" {
  count = var.create_shared_resources ? 1 : 0

  name               = "northbridge-github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust[0].json
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  count = var.create_shared_resources ? 1 : 0
  role  = aws_iam_role.github_actions_deploy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:PutImage", "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        # Every environment's ECR repos, not just the one this role happened to be
        # created from — this role is shared by every environment's app pipelines.
        Resource = ["arn:aws:ecr:*:*:repository/northbridge/*"]
      },
      {
        Sid      = "EcsDeploy"
        Effect   = "Allow"
        Action   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
        Resource = "*" # RegisterTaskDefinition does not support resource-level restriction
      },
      {
        Sid      = "EcsUpdate"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices", "ecs:DescribeTasks", "ecs:ListTasks"]
        Resource = "*"
      },
      {
        Sid      = "PassTaskRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::*:role/northbridge-*"
      },
      {
        Sid      = "SyncSpaBuckets"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::northbridge-applicant-portal-*", "arn:aws:s3:::northbridge-applicant-portal-*/*", "arn:aws:s3:::northbridge-reviewer-console-*", "arn:aws:s3:::northbridge-reviewer-console-*/*"]
      },
      {
        Sid      = "InvalidateCloudFront"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "*" # CloudFront distribution IDs vary per environment; ARNs aren't practical to enumerate here
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Broad terraform role — infra pipeline only, behind manual approval
# ---------------------------------------------------------------------------

resource "aws_iam_role" "github_actions_terraform" {
  count = var.create_shared_resources ? 1 : 0

  name               = "northbridge-github-actions-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_trust[0].json
}

resource "aws_iam_role_policy_attachment" "github_actions_terraform_power_user" {
  count      = var.create_shared_resources ? 1 : 0
  role       = aws_iam_role.github_actions_terraform[0].name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# PowerUserAccess deliberately excludes IAM management — this stack's Terraform creates
# IAM roles/policies (see iam.tf, this file), so the terraform role needs that back,
# scoped to this project's naming convention plus the one-per-account OIDC provider.
resource "aws_iam_role_policy" "github_actions_terraform_iam" {
  count = var.create_shared_resources ? 1 : 0
  role  = aws_iam_role.github_actions_terraform[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageProjectIamRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies", "iam:TagRole", "iam:UntagRole", "iam:PassRole",
        ]
        Resource = "arn:aws:iam::*:role/northbridge-*"
      },
      {
        Sid      = "ManageGithubOidcProvider"
        Effect   = "Allow"
        Action   = ["iam:GetOpenIDConnectProvider", "iam:CreateOpenIDConnectProvider", "iam:TagOpenIDConnectProvider", "iam:ListOpenIDConnectProviders"]
        Resource = "*"
      },
    ]
  })
}

output "github_actions_deploy_role_arn" {
  value = try(aws_iam_role.github_actions_deploy[0].arn, "not created in this workspace — see create_shared_resources")
}

output "github_actions_terraform_role_arn" {
  value = try(aws_iam_role.github_actions_terraform[0].arn, "not created in this workspace — see create_shared_resources")
}
