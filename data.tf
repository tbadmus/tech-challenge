data "aws_availability_zones" "available" {
  state = "available"

  # Local Zones and Wavelength Zones cannot host EKS nodes or NAT gateways.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Resolves an assumed-role session ARN back to the IAM role that issued it:
#
#   arn:aws:sts::<id>:assumed-role/<RoleName>/<session>
#     -> arn:aws:iam::<id>:role/aws-reserved/sso.amazonaws.com/<RoleName>
#
# String surgery cannot do this. The STS ARN drops the role's PATH, and every
# SSO permission-set role lives under /aws-reserved/sso.amazonaws.com/ -- so a
# hand-rolled regex produces an ARN that looks right and matches nothing.
# eks.tf uses this to tell whether the principal running the apply is already
# in cluster_admin_role_arns.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_caller_identity" "current" {}
