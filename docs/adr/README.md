# Architecture Decision Records

Each file records one decision: the context that forced it, the options that
were genuinely on the table, what was chosen, and what it costs. They are
written to be read by someone who was not in the room — which is the point,
since this repo is teaching material.

An ADR is immutable once accepted. If a decision is reversed, write a new
record that supersedes it rather than editing history.

| # | Decision | Status |
|---|---|---|
| [0001](0001-single-vpc.md) | Collapse the two-VPC + Transit Gateway topology to a single VPC | Accepted |
| [0002](0002-hybrid-modules.md) | Community modules for VPC and EKS, hand-rolled kept as teaching material | Accepted |
| [0003](0003-github-actions-oidc.md) | Replace Jenkins with GitHub Actions using OIDC federation | Accepted |
| [0004](0004-cluster-endpoint-posture.md) | Private endpoint access plus a narrow public allowlist | Accepted |
| [0005](0005-managed-node-groups.md) | Managed node groups now, Karpenter as a later phase | Accepted |
| [0006](0006-s3-native-state-locking.md) | S3 conditional-write locking instead of a DynamoDB table | Accepted |
| [0007](0007-dns-and-tls.md) | ExternalDNS + ACM for public DNS and TLS, gated on a resolvable domain | Accepted |
