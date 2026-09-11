variable "region" {
  description = "AWS region the cluster runs in."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket" {
  description = "Bucket holding the infrastructure root's state."
  type        = string
  default     = "tech-challenge-tfstate-841845498000"
}

variable "infra_state_key" {
  description = "State key of the infrastructure root for this environment."
  type        = string
  default     = "dev/terraform.tfstate"
}

variable "lb_controller_chart_version" {
  description = "aws-load-balancer-controller Helm chart version. Pinned so a cluster rebuild does not silently pick up a new controller."
  type        = string
  default     = "3.5.0"
}

variable "external_dns_chart_version" {
  description = "ExternalDNS Helm chart version."
  type        = string
  default     = "1.19.0"
}

variable "enable_dns" {
  description = "Run ExternalDNS. Mirrors the infrastructure root's enable_dns."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Apex domain ExternalDNS is allowed to manage."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "The single hosted zone ExternalDNS may write to."
  type        = string
  default     = ""
}
