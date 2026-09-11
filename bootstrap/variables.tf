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

# ---------------------------------------------------------------------------
# CI/CD — GitHub Actions OIDC
# ---------------------------------------------------------------------------

variable "enable_github_oidc" {
  description = "Create the IAM roles GitHub Actions assumes via OIDC. Requires github_repository."
  type        = bool
  default     = true

  validation {
    condition     = !var.enable_github_oidc || var.github_repository != ""
    error_message = "enable_github_oidc is true but github_repository is empty. `make` derives it from the git remote; set TF_VAR_github_repository explicitly if you are running terraform directly."
  }
}

variable "create_github_oidc_provider" {
  description = "Create the OIDC provider itself. Only one per AWS account is allowed, so set false if another stack already created it."
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "owner/name of the repository allowed to assume the CI roles. This value IS the security boundary -- never widen it to a wildcard. Deliberately has NO default: a fork inheriting the upstream repo name would create IAM roles trusting somebody else's repository. The Makefile derives it from `git remote get-url origin`."
  type        = string
  default     = ""

  validation {
    condition = (
      var.github_repository == "" ||
      can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    )
    error_message = "github_repository must be exactly owner/name, with no wildcards."
  }
}

variable "github_environments" {
  description = "GitHub Environment names permitted to assume the apply role. Environments carry the approval rules, which is why the trust policy binds to them rather than to branches."
  type        = list(string)
  default     = ["dev", "prod"]
}
