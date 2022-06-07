variable "user_name" {
  type = string
}

variable "groups" {
  type    = list(string)
  default = []
}
