# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "project" {
  description = "Project slug. Combined with environment to prefix every resource name."
  type        = string
  default     = "tech-challenge"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project))
    error_message = "project must be lowercase alphanumeric with hyphens, 2-21 characters."
  }
}

variable "environment" {
  description = "Deployment environment. Drives the name prefix, the state key and the durability defaults."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "region" {
  description = "AWS region to deploy into. Set per environment in environments/<env>.tfvars."
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Additional tags merged into the provider default_tags for every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Needs room for az_count public and az_count private subnets."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR of /20 or larger."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across. Three is the EKS default for a reason."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all private subnets instead of one per AZ. Cheap for dev, a single point of failure for prod."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

variable "cluster_version" {
  description = "Kubernetes minor version. Check the EKS version calendar before bumping."
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_public_access" {
  description = "Whether the API server is reachable from outside the VPC at all."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "Source CIDRs allowed to reach the public API endpoint. Never leave this as 0.0.0.0/0 -- that is the default the old code inherited by not setting it."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not an acceptable value. Use an allowlist, or set cluster_endpoint_public_access = false and reach the API over SSM."
  }

  # An empty list while public access is enabled is the dangerous case: the
  # community module's own default for this input is ["0.0.0.0/0"], so passing
  # nothing would silently restore the exposure ADR-0004 exists to remove.
  # Fail loudly instead.
  validation {
    condition = (
      !var.cluster_endpoint_public_access ||
      length(var.cluster_endpoint_public_access_cidrs) > 0
    )
    error_message = "cluster_endpoint_public_access is true but no CIDRs are allowlisted. Either add your egress IP (curl -s https://checkip.amazonaws.com) or set cluster_endpoint_public_access = false and use the SSM tunnel."
  }
}

variable "cluster_admin_role_arns" {
  description = "IAM role ARNs granted cluster-admin through EKS access entries. Typically SSO permission-set roles."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Node group
# ---------------------------------------------------------------------------

variable "node_instance_type" {
  description = "Single instance type for the managed node group. On-demand node groups take exactly one; a list is only valid for SPOT."
  type        = string
  default     = "t3.large"
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  description = "Minimum managed node group size."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum managed node group size."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Initial managed node group size. Ignored on subsequent applies so an autoscaler can own it."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Root volume size in GiB for each node."
  type        = number
  default     = 50
}

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

variable "ecr_repository_name" {
  description = "ECR repository for the demo application image."
  type        = string
  default     = "hello-world"
}

variable "ecr_image_retention_count" {
  description = "How many images to keep before the lifecycle policy expires the oldest."
  type        = number
  default     = 20
}

# ---------------------------------------------------------------------------
# VPC endpoints and observability
# ---------------------------------------------------------------------------

variable "enable_interface_endpoints" {
  description = "Create interface endpoints for ECR, logs, STS, SSM and friends. Roughly $0.01/hour/AZ each -- optional where a NAT gateway exists, mandatory for a fully private cluster."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch. Costs storage; buys the ability to answer 'why can this pod not reach that'."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs."
  type        = number
  default     = 14
}

# ---------------------------------------------------------------------------
# Control plane logging and SSM access host
# ---------------------------------------------------------------------------

variable "control_plane_log_retention_days" {
  description = "CloudWatch retention for EKS control plane logs. The old stack enabled all five log types with no retention, so they accrued forever."
  type        = number
  default     = 30
}

variable "create_ssm_host" {
  description = "Create a private, keyless instance for SSM port-forwarding to the cluster API. The ADR-0004 replacement for the public SSH bastion."
  type        = bool
  default     = true
}

variable "ssm_host_instance_type" {
  description = "Instance type for the SSM access host. It only terminates a port-forward."
  type        = string
  default     = "t3.micro"
}


# ---------------------------------------------------------------------------
# Public DNS and TLS
# ---------------------------------------------------------------------------

variable "enable_dns" {
  description = "Issue an ACM certificate and manage DNS. Requires an EXISTING, publicly resolvable domain with a Route53 hosted zone in this account -- ACM validates over public DNS, so an undelegated zone makes the apply hang until it times out."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Apex domain of an EXISTING Route53 hosted zone in this account, e.g. example.com. This stack never registers a domain -- see ADR-0007."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_dns || length(var.domain_name) > 0
    error_message = "enable_dns is true but domain_name is empty. Supply the apex domain of a hosted zone that already exists in this account."
  }
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for domain_name. Leave empty to look the zone up by name instead, which is usually what you want -- the ID differs in every account."
  type        = string
  default     = ""
}

variable "app_subdomain" {
  description = "Subdomain the demo app is served on, prepended to domain_name."
  type        = string
  default     = "hello"
}











# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "enable_container_insights" {
  description = "Install the amazon-cloudwatch-observability addon: Fluent Bit for logs plus Container Insights metrics."
  type        = bool
  default     = true
}

variable "container_log_retention_days" {
  description = "Retention for the Container Insights log groups. Left to create them itself the agent uses 'Never expire', which bills forever."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.container_log_retention_days)
    error_message = "Must be a retention value CloudWatch Logs accepts."
  }
}

variable "kms_key_deletion_window_in_days" {
  description = <<-EOT
    Waiting period before the cluster secret-encryption key is actually deleted
    (7-30 days). This window is the only undo for a key that still encrypts live
    Secrets, so prod keeps the 30-day default. A sandbox that is torn down and
    rebuilt daily accrues one orphaned key per cycle at ~$1/month each, which is
    why dev.tfvars sets 7.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}
