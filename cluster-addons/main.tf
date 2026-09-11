# ---------------------------------------------------------------------------
# Default StorageClass
# ---------------------------------------------------------------------------
# EKS ships a gp2 class on the legacy in-tree provisioner and -- verified
# against the live cluster -- does NOT mark it default, so any PVC that omits
# storageClassName stays Pending forever with no obvious cause. That is exactly
# what the old logging/elastic.yaml 30Gi claim would have hit.

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"

  # Close to mandatory on a multi-AZ cluster: Immediate binding will place a
  # volume in an AZ with no room for the pod, and the pod then never schedules.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller
# ---------------------------------------------------------------------------
# Subnet discovery is by tag, not configuration: the infrastructure root tags
# public subnets kubernetes.io/role/elb and private ones /internal-elb, so no
# subnet ID appears anywhere here.

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version
  namespace  = "kube-system"

  # Wait for the webhook to serve before any Ingress exists, or the first
  # Ingress admission request fails against a missing webhook.
  wait    = true
  timeout = 600

  values = [yamlencode({
    clusterName = local.cluster_name
    region      = var.region
    vpcId       = data.terraform_remote_state.infra.outputs.vpc_id

    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      # No eks.amazonaws.com/role-arn annotation: IAM arrives through the Pod
      # Identity association created in the infrastructure root. Annotating as
      # well would give the pod two credential sources.
    }

    replicaCount = 2

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }
  })]
}

# ---------------------------------------------------------------------------
# ExternalDNS
# ---------------------------------------------------------------------------
# The ALB is created by the load balancer controller, not Terraform, so
# Terraform never learns the hostname to write an alias for. ExternalDNS closes
# the loop from the other side by watching Ingress objects.

resource "helm_release" "external_dns" {
  count = var.enable_dns ? 1 : 0

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    provider = { name = "aws" }

    serviceAccount = {
      create = true
      name   = "external-dns"
    }

    # domainFilters alone is NOT enough. Registering the domain caused the
    # Route53 registrar to create a second hosted zone for the same name, and a
    # domain filter matches both -- ExternalDNS then wrote to the wrong one
    # every reconcile until the zone id filter was added.
    #
    # The chart has no first-class key for it: it must go through extraArgs. A
    # misnamed top-level `zoneIDFilters` is accepted by Helm and silently does
    # nothing, which is exactly how that was missed the first time.
    domainFilters = [var.domain_name]
    extraArgs     = ["--zone-id-filter=${var.hosted_zone_id}"]

    # sync, not upsert-only, so records are removed when an Ingress is deleted.
    # Safe because the TXT registry below means ExternalDNS only ever touches
    # records it created and marked as its own.
    policy     = "sync"
    txtOwnerId = local.cluster_name
    registry   = "txt"

    sources = ["ingress", "service"]

    resources = {
      requests = { cpu = "20m", memory = "64Mi" }
      limits   = { memory = "128Mi" }
    }
  })]
}
