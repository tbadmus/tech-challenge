# ---------------------------------------------------------------------------
# EKS cluster — ADR-0002 (community module), ADR-0004 (endpoint posture),
#               ADR-0005 (managed node groups)
# ---------------------------------------------------------------------------
# Replaces modules/eks, which resolved the IAM roles it needed through
# data.aws_iam_role lookups by name. Data sources carry no implicit dependency
# on the resources they read, which is why the old root module needed a
# hand-written five-entry depends_on to sequence a clean apply. Here the roles
# are created and referenced by the module that owns them, so the graph is real.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id = module.vpc.vpc_id

  # Nodes live only in private subnets. The ALB that reaches them is placed in
  # the public subnets by the load balancer controller in Phase 3, which can
  # target pod IPs across the boundary so the node never needs a public path.
  subnet_ids = module.vpc.private_subnets

  # --- ADR-0004: endpoint posture --------------------------------------------
  # The pre-modernization module set neither of these, so AWS defaulted to
  # public access from 0.0.0.0/0 with private access DISABLED -- the exact
  # inverse of what the architecture was built to achieve.
  endpoint_private_access = true
  endpoint_public_access  = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = (
    var.cluster_endpoint_public_access
    ? var.cluster_endpoint_public_access_cidrs
    : null
  )

  # --- Authorization ---------------------------------------------------------
  # "API" retires the aws-auth ConfigMap. Under the old setup the only cluster
  # administrator was whichever principal ran the first apply, and adding a
  # colleague meant hand-editing a ConfigMap in a live cluster -- the ClickOps
  # this project exists to eliminate. Access is now declared here and reviewed
  # in a pull request.
  authentication_mode = "API"

  access_entries = {
    for idx, arn in var.cluster_admin_role_arns : "admin-${idx}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Fallback, and only a fallback. When cluster_admin_role_arns is populated
  # the entries above are the grant, and asking the module to also add the
  # caller would create a SECOND access entry for the same principal -- which
  # EKS rejects with ResourceInUseException, after the cluster has already been
  # created. When the list is empty this keeps whoever applies from being locked
  # out of a cluster nobody can reach.
  enable_cluster_creator_admin_permissions = length(var.cluster_admin_role_arns) == 0

  # --- Control plane logging -------------------------------------------------
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = var.control_plane_log_retention_days

  # --- Addons ----------------------------------------------------------------
  # Previously unmanaged entirely. Pod Identity replaces IRSA as the way a pod
  # assumes an IAM role; the EBS CSI driver is required for any PersistentVolume
  # since the in-tree provisioner was removed in Kubernetes 1.23, which is why
  # the old Elasticsearch StatefulSet's 30Gi claim would have sat Pending.
  addons = {
    coredns                = {}
    kube-proxy             = {}
    eks-pod-identity-agent = { before_compute = true }
    metrics-server         = {}

    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        env = {
          # Hand pod ENIs out ahead of demand so scheduling is not gated on an
          # ENI attachment completing.
          WARM_PREFIX_TARGET = "1"
        }
      })
    }

    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  # --- Cluster security group ------------------------------------------------
  # The module's cluster security group allows 443 only from the node security
  # group, so by default nothing else in the VPC can reach the private API
  # endpoint -- including the SSM access host whose entire purpose is to reach
  # it. Found by actually testing the tunnel rather than assuming it worked.
  #
  # Contrast with the rule this replaces, which opened ports 0-65535 to an
  # entire peer VPC CIDR: one port, one named source security group.
  security_group_additional_rules = var.create_ssm_host ? {
    ssm_host_https = {
      description              = "HTTPS from the SSM access host, for kubectl over a port-forward"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      type                     = "ingress"
      source_security_group_id = aws_security_group.ssm[0].id
    }
  } : {}

  # --- Node group — ADR-0005 -------------------------------------------------
  eks_managed_node_groups = {
    default = {
      # AL2023. Amazon Linux 2 reached end of life in 2025 and EKS stopped
      # publishing AL2 AMIs for newer Kubernetes versions, so the old
      # ami_type = "AL2_x86_64" was a dead end independent of anything else.
      ami_type = "AL2023_x86_64_STANDARD"

      # Exactly one instance type. The old module passed a three-element list
      # with capacity_type = ON_DEMAND; managed node groups accept a list only
      # for SPOT, so that configuration could not apply. t3.small was also in
      # the list, and its pod-per-ENI limit is too low to be useful.
      instance_types = [var.node_instance_type]
      capacity_type  = var.node_capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      disk_size = var.node_disk_size

      labels = {
        role = "general"
      }
    }
  }

  tags = local.common_tags
}

# IAM role for the EBS CSI controller, assumed through Pod Identity rather than
# attached to the node role -- so only that controller gets EBS permissions
# instead of every pod on the node inheriting them.
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${local.cluster_name}-ebs-csi"

  attach_aws_ebs_csi_policy = true

  tags = local.common_tags
}
