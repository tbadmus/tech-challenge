# Partial backend configuration.
#
# Bucket, key and region are supplied per environment so that dev and prod
# never share a state file:
#
#   terraform init -backend-config=environments/dev.s3.tfbackend
#
# Locking uses S3 conditional writes (`use_lockfile`), available since
# Terraform 1.11. The separate DynamoDB lock table older guides describe is
# no longer required.

terraform {
  backend "s3" {}
}
