# ADR-0006 — S3 conditional-write locking instead of a DynamoDB table

**Status:** Accepted · 2026-09-10

## Context

The original backend named a bucket, `mvp-tfstate-bkt`, that no code in the
repo created — somebody had made it by hand. It specified one state key,
`lb-terraform.tfstate`, for every branch, and no locking of any kind. Two
concurrent Jenkins builds could corrupt state, and `dev` and `master` mutated
the same real infrastructure.

The conventional fix pairs an S3 backend with a DynamoDB table for lock
records. Since Terraform 1.11 the S3 backend can lock natively using S3
conditional writes, enabled with `use_lockfile = true`.

## Decision

S3 native locking. No DynamoDB table. State keys are per environment
(`dev/terraform.tfstate`, `prod/terraform.tfstate`) supplied through partial
backend configuration in `environments/*.s3.tfbackend`.

The bucket itself is created by the `bootstrap/` root module, which keeps local
state — the one deliberate exception, confined to four files, because the first
module cannot store state in the backend it is creating.

## Consequences

- One less resource, one less cost line, one less IAM permission.
- Requires Terraform 1.11 or newer. `required_version` enforces it, so an old
  binary fails with a clear message rather than silently running unlocked.
- Environments can no longer collide. `terraform init` must be re-run with a
  different `-backend-config` to switch, which the Makefile wraps.
- The bootstrap module's local state is not backed up. This is fine: it manages
  one bucket, and `terraform import` reconstructs it in a single command.
