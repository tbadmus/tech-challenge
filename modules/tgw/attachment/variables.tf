variable "vpc_id" {
  type    = string
  default = ""
}

variable "tgw_id" {
  type    = string
  default = ""
}

variable "subnet_ids" {
  default = []
  type    = list(string)
}

variable "name" {
  type    = string
  default = ""
}