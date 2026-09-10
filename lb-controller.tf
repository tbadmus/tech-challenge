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

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version
  namespace  = "kube-system"

  # Wait for the webhook to be serving before any Ingress is created, otherwise
  # the first Ingress admission request fails against a missing webhook.
  wait    = true
  timeout = 600

  values = [yamlencode({
    clusterName = module.eks.cluster_name
    region      = var.region
    vpcId       = module.vpc.vpc_id

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      # No eks.amazonaws.com/role-arn annotation: IAM arrives through the Pod
      # Identity association above, not IRSA. Annotating it as well would give
      # the pod two credential sources and make debugging ambiguous.
    }

    # Two replicas with leader election, spread across nodes. A single-replica
    # controller is a single point of failure for every Ingress in the cluster.
    replicaCount = 2

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }
  })]

  depends_on = [
    module.lb_controller_pod_identity,
    module.eks,
  ]
}
