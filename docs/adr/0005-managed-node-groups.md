# ADR-0005 — Managed node groups now, Karpenter as a later phase

**Status:** Accepted · 2026-09-10

## Context

The existing node group is misconfigured in two ways that matter.

It sets `instance_types = ["t3.medium", "t3.small", "t3.large"]` with
`capacity_type = "ON_DEMAND"`. Managed node groups accept a list only for
SPOT; an on-demand group takes exactly one type unless a launch template is
supplied. This is expected to fail at apply. Separately, `t3.small` has a low
pod-per-ENI limit and does not belong in a cluster at all.

It also sets `ami_type = "AL2_x86_64"`. Amazon Linux 2 reached end of life in
2025 and EKS stopped publishing AL2 AMIs for newer Kubernetes versions, so this
is a dead end regardless of the instance type.

Karpenter is what most teams building new clusters now reach for. It replaces
node groups with just-in-time provisioning, bin-packs better, and consolidates
underused nodes — and it demonstrates well, because you can watch it react.

## Decision

Managed node groups first, on AL2023, with a single instance type and a
correctly-sized group. Karpenter as a later phase once the stack is green end
to end.

## Consequences

- Fewer moving parts while the rest of the architecture is changing. When a
  deployment fails during Phases 1–4, the node layer is not a suspect.
- Karpenter needs a working cluster, Pod Identity, and a controller install
  path — all of which Phases 2 and 3 build anyway. Adding it later is additive,
  not a rewrite.
- `node_instance_type` is a single string, not a list, so the original mistake
  cannot recur through this interface.
- `desired_size` carries `ignore_changes` so an autoscaler can own it without
  fighting Terraform.
- Cost efficiency is left on the table in the meantime. Acceptable for a demo
  cluster that is destroyed between sessions.

## Alternatives considered

**Karpenter from the start.** Fewer migrations. Rejected: it couples the
node layer to the controller-install phase, and a failure during bring-up
becomes harder to attribute.

**Fargate.** No nodes to manage at all, but no DaemonSets — which rules out the
Fluent Bit logging path in ADR-0001's successor phases — and it teaches less
about how EKS actually schedules.
