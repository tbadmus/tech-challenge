# ADR-0008 — Own the cluster encryption key so its alias can carry a generated suffix

**Status:** Accepted · 2026-09-11

## Context

A pipeline apply failed after the VPC and the control plane had already been
built:

```
Error: creating KMS Alias (alias/eks/tech-challenge-dev-cluster):
AlreadyExistsException: An alias with the name
arn:aws:kms:us-east-1:<account>:alias/eks/tech-challenge-dev-cluster already exists
```

Nothing in this repository asked for that name. The EKS module creates the
cluster secret-encryption key itself and hardcodes the alias:

```hcl
computed_aliases = { cluster = { name = "eks/${var.name}" } }
```

It is not reachable through any input the module exposes. `kms_key_aliases`
adds *extra* aliases; it does not replace that one.

The alias was left over from an earlier teardown. That is the part worth
understanding, because it is not carelessness — it is a property of KMS.

Every other resource in this stack disappears when you delete it. KMS does not.
`ScheduleKeyDeletion` is the only delete there is, and it starts a 7-to-30 day
window during which the key still exists, still bills, and still owns its
aliases. AWS does not remove the aliases when the window opens. So the teardown
path has a step that no other service in the stack has: the alias must be
deleted *separately and explicitly*, and any teardown that does not — an
interrupted apply, a cancelled run, a hand-cleanup that scheduled the key and
stopped there — leaves behind a name that:

- nothing can reuse, because alias names are unique per account per region
- Terraform cannot see, because it is not in any state file
- fails the *next* build late, after the expensive resources already exist

Three such keys were sitting in the account in `PendingDeletion` when this was
diagnosed, and one still held the alias.

## Decision

Take ownership of the key. `create_kms_key = false`, an `aws_kms_key` in
`kms.tf`, and the ARN passed back through `encryption_config.provider_key_arn`.

The alias then uses **`name_prefix`, not `name`**, so the provider appends a
generated suffix:

```hcl
resource "aws_kms_alias" "eks" {
  name_prefix   = "alias/${local.cluster_name}-secrets-"
  target_key_id = aws_kms_key.eks.key_id
}
```

`environments/dev.tfvars` also drops the deletion window to the 7-day minimum.
Prod keeps 30.

## Consequences

- The suffix is generated once at create and stored in state. It is stable for
  the life of the stack — it does **not** re-roll on every apply — and a fresh
  create after a destroy gets a new one. A leftover alias from a previous life
  can no longer collide with anything.
- The key keeps the **default** key policy on a fresh create. That is
  deliberate: a default KMS policy is what allows an IAM policy to grant
  access, and the module already attaches exactly the right one to the cluster
  role — `aws_iam_policy.cluster_encryption`, whose `Resource` becomes
  `var.encryption_config.provider_key_arn` when `create_kms_key` is false.
  Writing our own key policy would need the cluster role ARN, which the module
  derives from the key ARN. The cycle is avoidable and not worth the paperwork.
- Orphaned *keys* still accumulate, one per teardown, until their window
  expires. Nothing can prevent that; the 7-day window in dev bounds it to about
  a dollar each.
- One thing this does **not** fix: `encryption_config` cannot be changed on a
  live cluster. EKS allows encryption to be *added* once and never altered, so
  moving an existing cluster onto a different key is a cluster replacement. The
  migration for the already-running dev cluster was therefore a state move —
  `terraform state mv module.eks.module.kms.aws_kms_key.this[0] aws_kms_key.eks`
  — which adopts the same key under the new address and leaves the cluster
  untouched. A fresh account needs none of this.

## Alternatives considered

**Clean up the alias before each apply.** A preflight that finds and deletes
orphaned aliases. Rejected: it deletes AWS resources outside Terraform, it
only covers the failure modes someone thought to enumerate, and it treats a
symptom that dynamic naming removes outright.

**Fix the teardown instead.** The alias only orphans because a destroy missed
it, so make destroy reliable. Rejected as *sufficient* — it is worth doing
anyway, but it cannot cover an apply that is cancelled halfway, which is
exactly how this one happened. Naming that cannot collide does not depend on
any teardown running to completion.

**Put the suffix in the cluster name.** Makes every dependent name dynamic too
— log groups, kubeconfig context, the `make tunnel` target, documentation. A
much larger blast radius for one alias.

**Drop secret encryption entirely.** Removes the key and the problem with it.
Rejected: envelope encryption of Secrets with a customer-managed key is a
control worth demonstrating, and the failure was a naming defect, not an
argument against the feature.
