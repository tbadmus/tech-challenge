locals {
  count = length(slice(data.aws_availability_zones.available.names, 0, 2))
}

variable "cidr" {
  type = string
}

variable "allowed_ip_range" {
  type    = string
  default = "0.0.0.0/0"
}

variable "is_public_required" {
  type    = bool
  default = true
}

variable "nat_gateway" {
  type    = bool
  default = true
}

variable "cluster_name" {
  type    = string
  default = null
}