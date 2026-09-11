# Bootstrap — remote state backend

Creates the S3 bucket that every other root module in this repo stores its
Terraform state in. Run once per AWS account.

```bash
export AWS_PROFILE=larry-cdw-sandadmin
cd bootstrap
terraform init
terraform apply
```

## Why this module keeps local state

Terraform state needs somewhere durable to live, but that somewhere is itself
infrastructure — so the very first module cannot use the backend it creates.
The usual answers are to create the bucket by hand (ClickOps, which this
project exists to avoid) or to accept one small module with local state. This
repo takes the second option and confines it to these four files.

The local state file is not precious. If it is lost, recover it with:

```bash
terraform import aws_s3_bucket.tfstate tech-challenge-tfstate-<account-id>
```

## Why there is no DynamoDB lock table

Older guides pair every S3 backend with a DynamoDB table for state locking.
Since Terraform 1.11 the S3 backend locks natively using conditional writes,
enabled by `use_lockfile = true` in the backend configuration. That removes a
resource, a small monthly cost, and an IAM permission from the design.

## Deliberate properties

| Setting | Why |
|---|---|
| `prevent_destroy` | A `terraform destroy` in this directory would take every environment's state with it |
| Versioning enabled | The only recovery path from a corrupted or truncated state write |
| Default encryption | State holds resource attributes in plaintext, including sensitive outputs |
| Public access blocked | Four separate flags, because any one of them alone is insufficient |
| `DenyInsecureTransport` | Rejects any request that is not over TLS |
| 90-day noncurrent expiry | Bounds the undo history so old versions do not accumulate forever |
