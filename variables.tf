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
  description = "AWS region to deploy into."
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
  default     = "1.34"
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
