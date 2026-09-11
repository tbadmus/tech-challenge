variable "project" {
  description = "Project slug, used in the bucket name."
  type        = string
  default     = "tech-challenge"
}

variable "region" {
  description = "Region to create the state bucket in. Must match the region in environments/*.s3.tfbackend."
  type        = string
  default     = "us-east-1"
}

variable "noncurrent_version_retention_days" {
  description = "How long superseded state versions are kept before expiry. This is your undo history -- do not set it low."
  type        = number
  default     = 90
}
