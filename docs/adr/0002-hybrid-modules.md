# ADR-0002 — Community modules for VPC and EKS, hand-rolled kept as teaching material

**Status:** Accepted · 2026-09-10

## Context

The repo contains eleven hand-written modules: `vpc`, `eks`, `ec2`, `ecr`,
three under `iam/`, three under `tgw/`. They were written in 2022 and show it —
the VPC module is capped at two AZs by a `slice()`, derives subnets from
undocumented `cidrsubnet` offsets, and creates a security group and a network
ACL that nothing consumes. The EKS module resolves IAM roles by name through
`data` sources rather than accepting ARNs, which is why the root module needs
hand-written `depends_on` lists.

Meanwhile `terraform-aws-modules/vpc/aws` and `terraform-aws-modules/eks/aws`
are used by a very large number of production estates, track new EKS features
within days, and handle the parts that are easy to get subtly wrong: subnet
tagging for load balancer discovery, IRSA and Pod Identity wiring, addon
lifecycle, node group launch templates.

But this repo is teaching material. A module that does everything for you
teaches nothing about what it is doing, and "call the module" is not a lesson a
junior engineer can carry to a different problem.

## Decision

Hybrid.

- **Community modules for VPC and EKS.** These are the two places where
  correctness is hardest and the blast radius of a mistake is largest, and
  where a reviewer would expect a production estate to use them.
- **Hand-rolled modules retained** under `modules/` for ECR, IAM and the
  optional TGW, where the resource count is small and the mapping from
  Terraform to AWS concept stays legible.
- **A teaching chapter** in the docs that reads the community module's output
  and explains what it generated and why — subnet maths, the tags the load
  balancer controller looks for, how IRSA trust policies are constructed.

## Consequences

- The demo is production-credible; a reviewer sees the modules they expect.
- The lesson survives, but as prose that explains generated infrastructure
  rather than as code a reader must not copy into production.
- New dependency surface: community module versions must be pinned and their
  upgrade notes read. This is a real ongoing cost and is accepted.
- The hand-rolled `vpc` and `eks` modules are deleted rather than left to rot
  as a second, diverging implementation.

## Alternatives considered

**Hand-rolled everything.** Maximum teaching value, and it is what the repo
does today. Rejected because the existing modules already demonstrate the
failure mode — two AZs, magic numbers, dead resources — and a reader cannot
tell which parts are deliberate.

**Community modules everywhere.** Shortest path to a working stack, and the
repo becomes a thin wrapper with nothing to teach.
