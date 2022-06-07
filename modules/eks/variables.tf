variable "name" {
  type = string
}

variable "role_name" {
  type = string
}

variable "node_role_name" {
  type = string
}

variable "node_group_name" {
  type    = string
  default = ""
}

variable "subnet_ids" {
  type = list(string)
}

variable "cluster_version" {
  type    = string
  default = "1.21"
}

variable "external_cidr" {
  type    = list(string)
  default = []
}
variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 1
}

variable "desired_size" {
  type    = number
  default = 1
}

variable "disk_size" {
  type    = number
  default = 50
}

variable "ami_type" {
  type    = string
  default = "AL2_x86_64"
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.medium", "t3.small", "t3.large"]
}