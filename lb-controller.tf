# ---------------------------------------------------------------------------
# AWS Load Balancer Controller — ADR-0001 consequence, answers review Q2
# ---------------------------------------------------------------------------
# The old Service carried service.beta.kubernetes.io/aws-load-balancer-internal
# and relied on the in-tree AWS cloud provider, which produces a Classic Load
# Balancer. Because it was internal, nothing outside the VPC could reach it --
# which is why the original README's final step was to SSH to a bastion and run
# curl.
#
# This controller changes the shape of the answer. With target-type: ip it
# registers pod IPs directly as ALB targets, so the load balancer sits in the
# public subnets while its targets stay in the private ones. The load balancer
# crosses the public/private boundary; the pod never does.
#
# Subnet discovery is by tag, not by configuration: network.tf already applies
# kubernetes.io/role/elb to public subnets and /internal-elb to private ones,
# so no subnet ID appears anywhere in this file.

module "lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  # Short deliberately: the module feeds this to aws_iam_role.name_prefix, which
  # AWS caps at 38 characters. "${local.cluster_name}-lb-controller" is 41 and
  # fails at plan time with a length error that does not mention IAM.
  name = "${local.name}-lbc"

  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }

  tags = local.common_tags
}

# The Helm release itself lives in cluster-addons/ -- see that module's README.
# Only the IAM half belongs here, because it is an AWS resource and needs no
# network path to the cluster.
