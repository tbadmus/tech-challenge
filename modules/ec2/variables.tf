variable "ami_id" {
  default = ""
  type    = string
}

variable "instance_type" {
  default = "t3.micro"
  type    = string
}

variable "iam_instance_profile" {
  type    = string
  default = ""
}

variable "name" {
  type    = string
  default = ""
}

variable "key_name" {
  default = ""
  type    = string
}

variable "subnet_id" {
  default = ""
  type    = string
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "bastion_ingress_rules" {
  type = list(object({
    description = string
    from_port   = number
    to_port     = string
    protocol    = string
    cidr_blocks = list(string)
  }))
}