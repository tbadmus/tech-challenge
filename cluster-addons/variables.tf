variable "region" {
  description = "AWS region the cluster runs in. Needed before the remote state can be read, which is why it is a variable rather than derived like everything else."
  type        = string
}

variable "state_bucket" {
  description = "Bucket holding the infrastructure root's state. Supplied by the Makefile, which derives it from the account id."
  type        = string
}

variable "infra_state_key" {
  description = "State key of the infrastructure root for this environment."
  type        = string
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



