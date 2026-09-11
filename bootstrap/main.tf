# ---------------------------------------------------------------------------
# Remote state backend
# ---------------------------------------------------------------------------
# The chicken-and-egg problem: Terraform state needs somewhere to live, but
# creating that somewhere is itself infrastructure. The old repo solved it by
# not solving it -- provider.tf simply named a bucket that no code created, so
# somebody had made it by hand in the console.
#
# This root module creates it in code, and runs with LOCAL state. That is the
# deliberate exception: exactly one small, rarely-changed root module keeps its
# state on disk, and everything else uses the bucket it produces. If this state
# file is ever lost, `terraform import` recovers it in a single command.
#
# There is no DynamoDB lock table here. Since Terraform 1.11, S3 conditional
# writes provide locking natively via `use_lockfile = true` in the backend
# config, which removes a resource, a cost line and a permission from the
# design that older guides still tell you to create.

data "aws_caller_identity" "current" {}

locals {
  # Account-suffixed because S3 bucket names are globally unique.
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # State is the record of every managed resource. Losing it to a stray
  # `terraform destroy` in this directory is not a recoverable mistake.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is what makes a corrupted or truncated state recoverable.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# State files contain resource attributes in plaintext -- IP addresses, ARNs,
# and any sensitive output a provider returns. This bucket is never public.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Keep the undo history bounded so old versions do not accumulate forever.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket     = aws_s3_bucket.tfstate.id
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Reject any plaintext PutObject/GetObject. Belt and braces alongside the
# bucket-level default encryption above.
resource "aws_s3_bucket_policy" "tfstate" {
  bucket     = aws_s3_bucket.tfstate.id
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
  policy     = data.aws_iam_policy_document.tfstate.json
}

data "aws_iam_policy_document" "tfstate" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
