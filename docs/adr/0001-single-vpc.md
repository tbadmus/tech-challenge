# ADR-0001 — Collapse the two-VPC topology to a single VPC

**Status:** Accepted · 2026-09-10

## Context

The original stack ran two VPCs joined by a Transit Gateway. `network1`
(10.0.0.0/16) held a public bastion, an internet gateway and a NAT gateway.
`network2` (172.31.0.0/16) had neither IGW nor NAT and held the EKS cluster.
`network2`'s default route pointed at the TGW, so a pod reaching the internet
left its VPC, crossed the gateway, and hairpinned out through the other VPC's
NAT.

The intent — keep worker nodes off the public internet — is still correct. The
question is whether a VPC boundary is what delivers it.

It is not. Containment comes from *subnet routing*: a node in a private subnet
has no public IP and no inbound path regardless of which VPC that subnet
belongs to. The split added a hop without adding isolation.

Three costs followed from it:

- **An unmanaged resource.** The TGW default-route-table entry was created by
  `routes.sh` through the AWS CLI, invoked from a `null_resource`, with all
  errors swallowed by `|| true`. It was not in state, so it was never planned,
  never recreated, and never destroyed.
- **A hidden dependency graph.** `module.eks2` needed a five-entry
  `depends_on` list to sequence around infrastructure Terraform could not see.
- **Roughly $70–75 per month** in attachment charges before data processing,
  for a demo cluster.

## Decision

One VPC, three availability zones, two subnet tiers: public subnets for the
ALB, NAT gateways and IGW; private subnets for nodes and pods.

The Transit Gateway modules move to `optional/` with their own README. Hub-and-
spoke is genuinely worth teaching — it is how multi-account and on-premises
connectivity actually work — but as something a reader stands up deliberately,
not as an unexplained dependency of the main path.

## Consequences

- `routes.sh`, `null_resource.sp` and the `null` provider are all deleted. The
  stack becomes fully declarative, and `terraform destroy` becomes reliable.
- Three AZs instead of two, matching EKS guidance.
- `single_nat_gateway` becomes a per-environment variable: one NAT in dev
  (~$32/mo, one shared failure domain), one per AZ in prod.
- The `external_cidr` security group rule that opened all 65,535 TCP ports to
  the peer VPC has no reason to exist and is removed with it.
- Anyone wanting the multi-VPC lesson must opt into it.

## Alternatives considered

**Keep both VPCs, model the TGW route properly.** Fixes the worst symptom and
leaves the cost and the hop. Rejected: it preserves complexity that buys
nothing.

**VPC peering instead of a Transit Gateway.** Cheaper, but still two VPCs, and
peering does not support transitive routing — so it solves the bill, not the
architecture.
