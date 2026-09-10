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
