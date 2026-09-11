# ---------------------------------------------------------------------------
# GitHub Actions OIDC — ADR-0003, amended
# ---------------------------------------------------------------------------
# This lives in bootstrap/ rather than the infrastructure root, and the reason
# is a bootstrapping failure we actually hit.
#
# The CI identity used to be created by the same root module it manages. So
# `terraform destroy` on the infrastructure removed the OIDC provider and both
# roles -- and CI could then no longer authenticate to rebuild what it had just
# torn down. Every pull request failed at "Configure AWS credentials via OIDC"
# until somebody ran an apply from a laptop. A CI identity that a routine
# teardown deletes is not a CI identity.
#
# bootstrap/ is the right home: it already exists to hold the things that must
# be there before anything else can run, it is applied once per account, and
# nothing in the normal deploy/destroy cycle touches it.
#
# Scope note: these roles are per-ACCOUNT, not per-environment. The apply role
# trusts both `environment:dev` and `environment:prod`, so one identity serves
# every environment in the account -- which is also why it does not belong in a
# root module that is instantiated per environment.
#
# THE TRUST POLICY IS THE SECURITY BOUNDARY. The `sub` claim must pin the
# repository AND the ref or environment. A policy matching `repo:owner/name:*`
# lets ANY branch -- including one pushed to a fork by a stranger opening a pull
# request -- assume the role. Everything below is StringEquals on explicit
# values for that reason.

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

  tags = { Name = "github-actions" }
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
  source = "../modules/iam/role"

  count = var.enable_github_oidc ? 1 : 0

  role_name          = "${var.project}-gha-plan"
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
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }

  statement {
    sid       = "StateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
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
  source = "../modules/iam/role"

  count = var.enable_github_oidc ? 1 : 0

  role_name          = "${var.project}-gha-apply"
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
    resources = [aws_s3_bucket.tfstate.arn]
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
