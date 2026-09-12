# Partial backend configuration.
#
# Bucket, key and region are supplied per environment so that dev and prod
# never share a state file:
#
#   make init ENV=dev
#
# The config is GENERATED into .backend/ at init time rather than committed,
# because the bucket name embeds the AWS account id.
#
# Locking uses S3 conditional writes (`use_lockfile`), available since
# Terraform 1.11. The separate DynamoDB lock table older guides describe is
# no longer required.

terraform {
  backend "s3" {}
}
