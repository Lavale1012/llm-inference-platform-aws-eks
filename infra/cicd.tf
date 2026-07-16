# CI/CD identity for GitHub Actions.
#
# GitHub Actions authenticates to AWS via OIDC (no long-lived access keys): the
# workflow presents a signed token from token.actions.githubusercontent.com and
# assumes the role below. The role's ECR *repository* authorization is granted
# separately by feeding its ARN into the compute module's ecr_push_role_arns
# (see main.tf); this file grants the *identity-side* permissions.

# GitHub's OIDC identity provider. Only one provider per URL is allowed per
# account. If the account already has one (e.g. created for another repo), do
# NOT let this create a duplicate — import it instead:
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com
# Check first: aws iam list-open-id-connect-providers
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprint is no longer verified by AWS for this provider
  # (AWS uses its own trust store for the well-known GitHub endpoint), but the
  # argument is still required. This is GitHub's published intermediate-cert
  # thumbprint.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Trust policy: allow the GitHub OIDC provider to assume this role, but only for
# this repository, and only from (a) the main branch or (b) pull requests. This
# scoping is what stops any other repo — or a fork's PR — from assuming the role.
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Audience must be sts.amazonaws.com (matches the workflow's aws-actions
    # configure-aws-credentials default).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to this repo's main branch and any PR against it.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${var.github_repository}:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions"
  description        = "Assumed by GitHub Actions (OIDC) for CI/CD: ECR push + terraform + EKS deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

# Identity-side permissions for the CI role. Repository-level ECR push/pull is
# additionally authorized by the ECR repository policy via ecr_push_role_arns;
# ecr:GetAuthorizationToken is account-wide and must live here.
data "aws_iam_policy_document" "github_actions" {
  # ECR: obtain a login token, then push/pull layers to the project repo.
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [module.compute.ecr_repository_arn]
  }

  # EKS: describe the cluster so `aws eks update-kubeconfig` works. Actual
  # in-cluster (kubectl) authorization comes from the EKS access entry wired in
  # the compute module, not from IAM.
  statement {
    sid       = "EksDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [module.compute.cluster_arn]
  }

  # Terraform remote state: read/write the state object and the S3 native lock.
  statement {
    sid       = "TfStateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.project_name}-tfstate-${var.aws_region}"]
  }

  statement {
    sid    = "TfStateObjectRW"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::${var.project_name}-tfstate-${var.aws_region}/*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project_name}-github-actions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}
