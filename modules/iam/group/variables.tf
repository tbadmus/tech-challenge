variable "group_name" {
  type = string
}

variable "path" {
  type    = string
  default = "/"
}

variable "policies" {
  type    = map(any)
  default = {}
}

variable "managed_policies" {
  type    = list(string)
  default = []
}

variable "users" {
  type    = list(string)
  default = []
}
