# ---------------------------------------------------------------------------
# Observability — Fluent Bit to CloudWatch, replacing the self-managed EFK stack
# ---------------------------------------------------------------------------
# The amazon-cloudwatch-observability addon installs Fluent Bit as a DaemonSet
# and the CloudWatch agent for Container Insights. It replaces an Elasticsearch
# StatefulSet, a Fluentd DaemonSet and a Kibana Deployment -- see optional/efk/
# for what was wrong with those, the short version being that the Elasticsearch
# PVC could never have bound on a modern cluster.
#
# This lives in the INFRASTRUCTURE root, not cluster-addons/, because
# aws_eks_addon is an AWS API resource. Terraform needs no network path to the
# Kubernetes API to manage it, so it still plans from a hosted CI runner.

# Log groups are created HERE, ahead of the agent, specifically so retention is
# set. Left to create them itself, Container Insights makes these groups with
# retention "Never expire" -- logs accumulate and bill forever, which is the
# same defect the review flagged in the original stack's control plane logging.
resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = var.enable_container_insights ? toset([
    "application", # container stdout/stderr
    "dataplane",   # kubelet, containerd, kube-proxy
    "host",        # /var/log/messages, secure, dmesg
    "performance", # Container Insights embedded metrics
  ]) : toset([])

  name              = "/aws/containerinsights/${local.cluster_name}/${each.key}"
  retention_in_days = var.container_log_retention_days

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-${each.key}" })
}

# The agent's IAM, through Pod Identity rather than the node role, so only the
# CloudWatch agent can write metrics and logs instead of every pod on the node
# inheriting that permission.
module "cloudwatch_observability_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  count = var.enable_container_insights ? 1 : 0

  # Short on purpose: the module feeds this to aws_iam_role.name_prefix, which
  # AWS caps at 38 characters.
  name = "${local.name}-cwobs"

  attach_aws_cloudwatch_observability_policy = true

  # Deliberately NO `associations` block here. The rule across this repo:
  #
  #   managed EKS addon  -> the ADDON declares pod_identity_association
  #   Helm release       -> the pod-identity MODULE declares associations
  #
  # Doing both creates two associations for the same namespace/service-account
  # pair, and EKS rejects the second with
  # "ResourceInUseException: Association already exists" -- which fails the
  # addon create, not the association create, so the error names the wrong
  # resource. aws-ebs-csi-driver follows the same rule; the load balancer
  # controller and ExternalDNS are Helm releases and so take the other branch.

  tags = local.common_tags
}
