data "aws_availability_zones" "available" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bastion-ami-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [data.aws_caller_identity.current.id]
}

data "aws_iam_policy_document" "bastion-policy" {
  statement {
    sid = "StartSessionAccess"

    actions = [
      "ssm:StartSession",
    ]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:instance/*",
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:document/SSM-SessionManagerRunShell"
    ]

    condition {
      test     = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"

      values = [
        "true",
      ]
    }
  }

  statement {
    actions = [
      "ssm:DescribeSessions",
      "ssm:GetConnectionStatus",
      "ssm:DescribeInstanceProperties",
      "ec2:DescribeInstances",
    ]

    resources = [
      "*",
    ]
  }

  statement {
    actions = [
      "ssm:TerminateSession",
      "ssm:ResumeSession",
    ]

    resources = [
      "arn:aws:ssm:*:*:session/$${aws:username}-*",
    ]
  }
}

data "aws_iam_policy_document" "eks-assume-role-policy" {
  statement {
    sid = "EKSAssumeAccess"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "node-assume-role-policy" {
  statement {
    sid = "EKSAssumeAccess"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "bastion-assume-role-policy" {
  statement {
    sid = "BastionAssumeAccess"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
