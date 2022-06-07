variable "role_name" {
  type = string
}

variable "assume_role_policy" {
  type    = string
  default = ""
}

variable "is_instance_profile_req" {
  default = false
  type    = bool
}

variable "inline_policies" {
  type    = map(string)
  default = {}
}
variable "managed_policy_arns" {
  type    = list(string)
  default = []
}
