output "bucket_name" {
  description = "State bucket name. Must match `bucket` in environments/*.s3.tfbackend."
  value       = aws_s3_bucket.tfstate.id
}

output "backend_config_snippet" {
  description = "Paste-ready backend configuration for a new environment."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.tfstate.id}"
    key          = "<environment>/terraform.tfstate"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}

output "github_actions_plan_role_arn" {
  description = "Role assumed by pull-request plan jobs. Read-only plus state locking."
  value       = try(module.gha_plan_role[0].role_arn, "")
}

output "github_actions_apply_role_arn" {
  description = "Role assumed by apply jobs running in a protected GitHub Environment."
  value       = try(module.gha_apply_role[0].role_arn, "")
}
