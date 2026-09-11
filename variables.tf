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
  description = "Issue an ACM certificate and run ExternalDNS. Requires a PUBLICLY RESOLVABLE domain -- ACM validates over public DNS, so an undelegated zone makes the apply hang until it times out."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Apex domain of the Route53 hosted zone, e.g. example.com."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for domain_name."
  type        = string
  default     = ""
}

variable "app_subdomain" {
  description = "Subdomain the demo app is served on, prepended to domain_name."
  type        = string
  default     = "hello"
}


# ---------------------------------------------------------------------------
# Domain registration
# ---------------------------------------------------------------------------

variable "register_domain" {
  description = "Register domain_name through Route53 Domains. THIS SPENDS MONEY and the charge is not refundable; `terraform destroy` does not unregister. Leave false unless you mean it."
  type        = bool
  default     = false
}

variable "domain_duration_years" {
  description = "Registration period in years."
  type        = number
  default     = 1
}

variable "domain_auto_renew" {
  description = "Auto-renew the registration each year. Off by default so a demo domain does not become a standing bill."
  type        = bool
  default     = false
}

variable "domain_name_servers" {
  description = "Hostnames to delegate the registration to. Set these to an EXISTING hosted zone's delegation set, otherwise Route53 creates a second zone and orphans the first. Get them with: aws route53 get-hosted-zone --id <zone-id> --query DelegationSet.NameServers"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.domain_name_servers) == 0 || length(var.domain_name_servers) >= 2
    error_message = "A registration needs at least two nameservers."
  }

  # The expensive mistake this catches: registering without pinning nameservers
  # makes Route53 create a NEW hosted zone, delegate the domain to it, and leave
  # the existing zone -- with every record this stack manages -- orphaned and
  # unreachable. Unpicking that after the fact means a delegation change and
  # waiting out TTLs.
  validation {
    condition     = !var.register_domain || length(var.domain_name_servers) >= 2
    error_message = "register_domain is true but domain_name_servers is empty. Pin the existing hosted zone's delegation set, or Route53 will create a second zone and orphan the current one. Get them with: aws route53 get-hosted-zone --id <zone-id> --query DelegationSet.NameServers"
  }
}

variable "domain_contact" {
  description = "Registrant, admin and tech contact for the registration. Real details are required by the registrar. Keep them in a gitignored tfvars file -- never commit them."
  sensitive   = true

  type = object({
    contact_type      = optional(string, "PERSON")
    organization_name = optional(string)
    first_name        = string
    last_name         = string
    address_line_1    = string
    city              = string
    state             = string
    country_code      = string
    zip_code          = string
    phone_number      = string
    email             = string
  })

  default = {
    first_name     = ""
    last_name      = ""
    address_line_1 = ""
    city           = ""
    state          = ""
    country_code   = "US"
    zip_code       = ""
    phone_number   = ""
    email          = ""
  }

  validation {
    condition     = var.domain_contact.phone_number == "" || can(regex("^\\+[0-9]{1,3}\\.[0-9]{6,14}$", var.domain_contact.phone_number))
    error_message = "phone_number must be in the registrar's format: a plus sign, country code, a dot, then the number. For example +1.5551234567."
  }
}

# ---------------------------------------------------------------------------
# CI/CD — GitHub Actions OIDC
# ---------------------------------------------------------------------------

variable "enable_github_oidc" {
  description = "Create the IAM roles GitHub Actions assumes via OIDC."
  type        = bool
  default     = true
}

variable "create_github_oidc_provider" {
  description = "Create the OIDC provider itself. Only one per AWS account is allowed, so set false if another stack already created it."
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "owner/name of the repository allowed to assume the CI roles. This value IS the security boundary -- never widen it to a wildcard."
  type        = string
  default     = "tbadmus/tech-challenge"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be exactly owner/name, with no wildcards."
  }
}

variable "github_environments" {
  description = "GitHub Environment names permitted to assume the apply role. Environments carry the approval rules, which is why the trust policy binds to them rather than to branches."
  type        = list(string)
  default     = ["dev", "prod"]
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
