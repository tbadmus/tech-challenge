# ---------------------------------------------------------------------------
# Default StorageClass — defect carried over from Phase 2
# ---------------------------------------------------------------------------
# EKS ships a StorageClass named gp2 that uses the legacy in-tree provisioner
# (kubernetes.io/aws-ebs) and -- verified against the live cluster -- does NOT
# carry the is-default-class annotation. The consequence is that any PVC which
# omits storageClassName stays Pending forever with no obvious cause.
#
# That is exactly the failure the old logging/elastic.yaml would have hit: a
# 30Gi volumeClaimTemplate with no storageClassName, on a cluster with no
# default class and no CSI driver installed.
#
# gp3 rather than gp2: cheaper per GiB, and baseline 3000 IOPS / 125 MiB/s
# independent of volume size, where gp2 scales IOPS with capacity.

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"

  # Bind only once a pod is scheduled, so the volume is created in the same AZ
  # as the pod that needs it. WaitForFirstConsumer is close to mandatory on a
  # multi-AZ cluster -- Immediate binding will happily place a volume in an AZ
  # with no capacity for the pod, and the pod then never schedules.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }

  depends_on = [module.eks]
}
