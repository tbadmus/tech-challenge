# ADR-0009 — CI builds and publishes; something with a network path deploys

**Status:** Accepted · 2026-09-12

## Context

`app-deploy.yml` runs `kubectl` from a GitHub-hosted runner, in its preflight
checks and again in the deploy job. Under this architecture that cannot work,
and the reason is not a misconfiguration to be fixed.

ADR-0004 gives the cluster a private endpoint plus a public one restricted to an
explicit CIDR allowlist. A GitHub-hosted runner satisfies neither condition. It
is not in the VPC, so the private endpoint is unreachable. Its egress address is
drawn from a large, shifting pool that AWS has never heard of, so the public
endpoint rejects it. There is no value of `cluster_endpoint_public_access_cidrs`
short of the whole internet that admits a hosted runner and still means
anything.

This went unnoticed for an embarrassing reason: the job has never run. Every
`app-deploy` run so far failed or was cancelled in an earlier job — Trivy, then
an ordering bug — so `deploy` was always skipped. A workflow that cannot succeed
looked identical to a workflow that had not been tried.

Two related defects were found while establishing this and are already fixed.
The preflight reported *any* non-zero `kubectl` exit as "the load balancer
controller is not installed", so an unreachable API produced a confident
instruction to run `make addons-apply`, which could not have helped. And the
substitution that injects the image digest was silently a no-op, so the job
would have deployed an unpullable placeholder even if it had had a network path.
Neither is the subject of this record; both are why it was written.

## Decision

CI owns build, scan and publish. Deployment happens where a network path to the
Kubernetes API already exists.

Concretely: `scan` and `build` always run, and the run ends with the image
pushed to ECR by digest and a job summary naming the digest and the two commands
that deploy it. The `deploy` job and the two in-cluster preflight checks are
gated on a repository variable, `APP_DEPLOY_FROM_CI`, which defaults to unset.

The variable is the honest part of this. The pipeline is not permanently
incapable of deploying — it is incapable *from a hosted runner against a
restricted endpoint*. Give it a runner with a path and it works, and the flag is
where you say so.

## Consequences

- The pipeline stops claiming to do something it cannot. A red run now means
  something is broken, rather than "this repository is configured the way it was
  designed to be".
- `make deploy` is a real step in the documented sequence rather than a fallback
  — see steps 8 and 9 of the consumption guide. The nine-step guide already
  drew the line in the same place, between the stages that talk to AWS APIs and
  the stages that talk to the Kubernetes API.
- The image is still built, scanned and pushed by CI on every merge, so the
  supply-chain half of the pipeline is unaffected. What CI stops doing is the
  last step.
- Someone who wants full CI deployment has to make a real infrastructure
  decision and record it, rather than discovering the gap through a timeout.
- A deploy that runs from a workstation is a deploy that is not reproducible
  from the repository alone. That is a genuine loss and the main argument for
  revisiting this.

## Alternatives considered

**Allowlist GitHub's egress ranges.** They are published, so this is
mechanically possible. Rejected: the list is thousands of prefixes, it changes
without notice, and it authorises every GitHub Actions runner in the world, not
ours. It converts a meaningful control into a formality while leaving the
paperwork of having one.

**Make the endpoint fully public.** Access entries and RBAC still gate what a
caller can do, so this is not as reckless as it sounds. Rejected because it
discards ADR-0004 to solve a deployment-plumbing problem, and because the
allowlist is the control this project exists to demonstrate.

**Self-hosted runner in a private subnet.** The direct fix, and the one
`APP_DEPLOY_FROM_CI` is designed to switch on. Not adopted now because it adds a
runner to operate, patch and secure — a standing cost for a demo cluster that is
destroyed between sessions, and one that pulls the project toward managing CI
infrastructure rather than demonstrating EKS. Right answer for a real team.

**Drive the deploy through something already inside the VPC** — CodeBuild in a
private subnet, or SSM Run Command against the access host. Both work and
neither needs an inbound path. Rejected as the default because each adds a
second deployment mechanism to explain and keep working, and the SSM variant in
particular turns the jump host into a deployment dependency it was not built to
be.

**Pull-based GitOps — Argo CD or Flux in the cluster.** The strongest answer,
and the one to revisit first. The cluster reconciles itself from git, so no
external system ever needs inbound access and the restricted endpoint stops
being an obstacle at all. CI's job shrinks to pushing an image and updating a
manifest reference. Not adopted here only because it is a phase of work rather
than a flag: it changes how deployment is modelled, needs its own bootstrap
story, and would deserve an ADR of its own. Recorded as the intended successor
to this decision.
