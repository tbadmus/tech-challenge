# ADR-0004 — Private endpoint access plus a narrow public allowlist

**Status:** Accepted · 2026-09-10

## Context

`modules/eks/main.tf` set only `subnet_ids` inside `vpc_config`. AWS then
applied its defaults: `endpoint_public_access = true`,
`public_access_cidrs = ["0.0.0.0/0"]`, `endpoint_private_access = false`.

So the cluster the architecture was built to keep private published its API
server to the entire internet. IAM still gated authentication, so this was not
an open cluster — but the network posture was the inverse of the intent, and
the README's justification for the bastion ("cannot be accessed from local
without VPN") was true only of the internal load balancer, never of the API.

Three postures were considered:

**A — public endpoint, CIDR allowlist.** Simplest. No bastion. The catch is
that hosted CI runners publish wide and shifting IP ranges, so an allowlist
that covers CI stops being an allowlist.

**B — private access on, public access restricted to a small human allowlist,
SSM port-forward for everything else.**

**C — fully private endpoint.** Closest to enterprise reality. Requires the
complete VPC endpoint set — `ecr.api`, `ecr.dkr`, `logs`, `sts`, `ec2`,
`elasticloadbalancing`, plus the S3 gateway endpoint — or image pulls and log
shipping fail with no obvious cause.

## Decision

Option B for dev; the variables support option C, and `environments/prod.tfvars`
sets `cluster_endpoint_public_access = false` so the difference is visible as
configuration rather than as forked code.

Operator access is by SSM port-forward, not SSH:

```bash
aws ssm start-session --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["$EKS_ENDPOINT"],"portNumber":["443"],"localPortNumber":["8443"]}'
```

Authorization is handled separately and in code: `authentication_mode = "API"`
with `aws_eks_access_entry` resources mapping SSO permission-set roles. The old
stack set no `access_config`, so it fell back to the `aws-auth` ConfigMap where
the only administrator was whoever ran the first apply — making "add a
colleague" a manual edit against a live cluster, which is precisely the
ClickOps this project exists to eliminate.

## Consequences

- The public bastion, the shared `mvp` key pair, the `techkey` private key
  written into the repo root, and the `0.0.0.0/0` rule on port 22 are all
  deleted. The AMI already installs `amazon-ssm-agent` and the instance role
  already carries `AmazonSSMManagedInstanceCore`, so this path was mostly built
  and simply unused.
- Every operator session is recorded in CloudTrail, which SSH was not.
- `cluster_endpoint_public_access_cidrs` carries a validation rule rejecting
  `0.0.0.0/0` outright — the failure here was silence, so the configuration
  refuses to be silent about it again.
- Anyone outside the allowlist needs an SSM-capable instance to exist. In dev,
  that is one t3.micro.
- Moving dev to option C later means adding the VPC endpoints first, not
  flipping a flag.
