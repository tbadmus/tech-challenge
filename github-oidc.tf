# ---------------------------------------------------------------------------
# GitHub Actions OIDC — ADR-0003
# ---------------------------------------------------------------------------
# Replaces the static AWS credentials the Jenkins controller held. GitHub mints
# a short-lived OIDC token per job; AWS exchanges it for a role session. No
# long-lived access key exists anywhere in the system, so there is nothing to
# leak, rotate, or find in a build log.
#
# THE TRUST POLICY IS THE SECURITY BOUNDARY. The `sub` claim must pin the
# repository AND the ref or environment. A policy that matches
# `repo:owner/name:*` lets ANY branch -- including one pushed to a fork by a
# stranger opening a pull request -- assume the role. Everything below is
# written as StringEquals on explicit values for that reason.

data "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc && !var.create_github_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc && var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # No thumbprint_list: AWS verifies token.actions.githubusercontent.com against
  # its own trusted CA library, so the old ritual of pasting a GitHub
  # certificate fingerprint here -- and updating it whenever GitHub rotated --
  # is obsolete.

  tags = merge(local.common_tags, { Name = "github-actions" })
}

locals {
  github_oidc_arn = var.enable_github_oidc ? (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  ) : ""

  github_oidc_url = "token.actions.githubusercontent.com"
}

# --- Plan role: pull requests ----------------------------------------------
# Runs on untrusted input. A pull request can come from a fork, and the
# workflow it triggers is whatever that branch contains. This role must
# therefore be able to read everything and change nothing.

data "aws_iam_policy_document" "gha_plan_assume" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Pull requests only. Not a wildcard.
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:sub"
      values   = ["repo:${var.github_repository}:pull_request"]
    }
  }
}

module "gha_plan_role" {
  source = "./modules/iam/role"

  count = var.enable_github_oidc ? 1 : 0

  role_name          = "${local.name}-gha-plan"
  assume_role_policy = data.aws_iam_policy_document.gha_plan_assume[0].json

  managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  inline_policies = {
    # `terraform plan` takes a state lock, so read-only is not quite enough --
    # it needs to write and delete the lock object itself.
    "state-lock" = data.aws_iam_policy_document.gha_state_lock[0].json
  }
}

data "aws_iam_policy_document" "gha_state_lock" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    sid    = "StateObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:aws:s3:::${var.project}-tfstate-${data.aws_caller_identity.current.account_id}/*"]
  }

  statement {
    sid       = "StateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"]
  }
}

# --- Apply role: protected environments only --------------------------------

data "aws_iam_policy_document" "gha_apply_assume" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to GitHub Environments rather than branches. The environment is
    # what carries the human approval rule, so binding the AWS role to it means
    # the approval gate cannot be bypassed by pushing to a branch.
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:sub"
      values   = [for e in var.github_environments : "repo:${var.github_repository}:environment:${e}"]
    }
  }
}

module "gha_apply_role" {
  source = "./modules/iam/role"

  count = var.enable_github_oidc ? 1 : 0

  role_name          = "${local.name}-gha-apply"
  assume_role_policy = data.aws_iam_policy_document.gha_apply_assume[0].json

  # Honest compromise, flagged rather than hidden. This stack creates VPCs, EKS
  # clusters, IAM roles, ACM certificates and Route53 records, so a genuinely
  # least-privilege policy for it would be enormous, brittle, and would break on
  # every new resource type. The production answer is a permissions boundary on
  # everything this role creates, plus a curated policy -- real work, and worth
  # doing before this pattern goes anywhere near a production account.
  #
  # The explicit deny below is the mitigation that costs nothing: a few actions
  # that CI has no business performing, denied outright. An explicit Deny always
  # beats any Allow, including one inside AdministratorAccess.
  managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]

  inline_policies = {
    "ci-guardrails" = data.aws_iam_policy_document.gha_guardrails[0].json
  }
}

data "aws_iam_policy_document" "gha_guardrails" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    sid    = "NeverDestroyStateBucket"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketVersioning",
      "s3:PutBucketPolicy",
    ]
    resources = ["arn:aws:s3:::${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"]
  }

  statement {
    sid    = "NeverTouchDomainRegistrations"
    effect = "Deny"
    # Registering, transferring or deleting a domain is a money-spending,
    # largely irreversible act. It stays a human decision -- see ADR-0007.
    actions   = ["route53domains:*"]
    resources = ["*"]
  }

  statement {
    sid    = "NeverTouchAccountOrOrg"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
      "iam:CreateUser",
      "iam:CreateAccessKey",
    ]
    resources = ["*"]
  }
}
