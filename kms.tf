# ---------------------------------------------------------------------------
# Cluster secret encryption key — owned here rather than by the EKS module
# ---------------------------------------------------------------------------
# EKS envelope-encrypts Kubernetes Secrets with a customer-managed KMS key. The
# community module will create that key for you, and by default it does, but it
# also hardcodes the alias:
#
#   computed_aliases = { cluster = { name = "eks/${var.name}" } }
#
# That name is fixed, account-unique, and not overridable by any input the
# module exposes. It is also the one name in this stack that a teardown can
# leave behind, because KMS is the one service here that cannot delete
# immediately: scheduling a key for deletion starts a 7-to-30 day window, and
# the key -- along with anything still pointing at it -- survives that whole
# window. A teardown that removes the key but misses the alias leaves a name
# sitting in the account that nothing can reuse and terraform cannot see, and
# the next apply dies on:
#
#   AlreadyExistsException: An alias with the name
#   arn:aws:kms:...:alias/eks/tech-challenge-dev-cluster already exists
#
# after the VPC and the control plane have already been built. That is exactly
# what happened on 2026-09-11.
#
# Owning the key moves the alias under our control, and `name_prefix` lets the
# provider append a random suffix. Two consequences worth being explicit about:
#
#   - the suffix is generated once, at create, and stored in state, so it is
#     stable for the life of the stack -- it is not re-rolled on every apply
#   - a fresh create after a destroy gets a NEW suffix, so a leftover alias
#     from a previous life can no longer collide with it
#
# The key itself keeps the DEFAULT key policy (account root full access), which
# is what lets an IAM policy grant access. The module attaches exactly that
# policy to the cluster role -- see aws_iam_policy.cluster_encryption, whose
# Resource is var.encryption_config.provider_key_arn when create_kms_key is
# false. Writing our own key policy here instead would need the cluster role
# ARN, which the module creates from the key ARN, and the cycle is not worth
# the paperwork.

resource "aws_kms_key" "eks" {
  description = "${local.cluster_name} Kubernetes secret envelope encryption"

  enable_key_rotation     = true
  deletion_window_in_days = var.kms_key_deletion_window_in_days

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-secrets" })
}

resource "aws_kms_alias" "eks" {
  # name_prefix, never name. This is the whole point of the file.
  name_prefix   = "alias/${local.cluster_name}-secrets-"
  target_key_id = aws_kms_key.eks.key_id
}
