variable "repo_name" {
  description = "Repository name."
  type        = string
}

variable "image_tag_mutability" {
  description = "IMMUTABLE stops a pushed tag from being moved. Requires callers to tag by commit SHA or digest rather than reusing :latest."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Run a BASIC vulnerability scan on every push. Free."
  type        = bool
  default     = true
}

variable "image_retention_count" {
  description = "How many tagged images to keep before the lifecycle policy expires the oldest."
  type        = number
  default     = 20
}

variable "force_delete" {
  description = "Allow terraform destroy to delete the repository while it still contains images."
  type        = bool
  default     = false
}
