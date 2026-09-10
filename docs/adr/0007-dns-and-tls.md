# ADR-0007 — Public DNS via ExternalDNS, TLS via ACM, both gated on a resolvable domain

**Status:** Accepted · 2026-09-10

## Context

Phase 3 left the demo reachable at the ALB's own AWS hostname over plain HTTP.
That works, but it is not what a reviewer or a student should see: no TLS, and
a hostname nobody can read.

The account has one Route53 hosted zone, `elbeetest.com`, so the obvious move
was to serve the app at `hello.elbeetest.com` with an ACM certificate.

**That domain is not registered.** `whois elbeetest.com` returns "No match", and
the `.com` gTLD servers return SOA rather than a delegation. The hosted zone
exists; nothing on the public internet resolves it.

This is not cosmetic. ACM validates a DNS-validated certificate by resolving
the validation CNAME over **public** DNS. On an undelegated zone the record is
written, ACM never sees it, the certificate sits in `PENDING_VALIDATION`, and
`aws_acm_certificate_validation` blocks `terraform apply` until it times out.
The stranded `_39197f6e...` CNAME already in that zone, and the `EXPIRED`
`vividsol-sub.com` certificate in ACM, are both fossils of this same attempt.

## Decision

Build the DNS and TLS layer completely, and gate all of it on `enable_dns`,
defaulting to **false**.

- **ACM certificate** with DNS validation, `create_before_destroy` so a
  rotation never leaves the listener without one, and a 10-minute validation
  timeout instead of the 45-minute default — if validation has not completed by
  then the cause is almost always delegation, and failing fast says more than
  hanging.
- **ExternalDNS** rather than a Terraform `aws_route53_record`. The ALB is
  created by the load balancer controller, not by Terraform, so Terraform never
  learns the hostname to alias. ExternalDNS closes the loop from the other side:
  it watches Ingress objects and writes records for the hostnames they declare.
- **A Kustomize overlay** (`app/k8s-tls`) adds the HTTPS listener, the
  `ssl-redirect`, and the public host, so turning TLS on is a deploy-time switch
  rather than an edit to the base manifests.

## Consequences

- The demo runs on HTTP at the ALB hostname until a resolvable domain exists.
  Enabling it later is `enable_dns = true` plus `domain_name` and
  `hosted_zone_id`, then `make apply && make deploy-tls`.
- ExternalDNS runs with `policy = sync` and a **TXT registry** keyed on the
  cluster name. It therefore only ever modifies records it created and marked
  as its own, which is what makes it safe to point at a zone containing records
  this stack does not manage. `zoneIDFilters` and `domainFilters` narrow it
  further, and its IAM role is scoped to a single hosted zone ARN.
- `ssl-redirect` is enforced at the ALB, so no request reaches a pod in
  plaintext. TLS terminates at the load balancer; traffic from ALB to pod stays
  inside the VPC.

## Amendment — registration is in the project

`aws_route53domains_domain` registers a domain, so the registration itself is
now `domain.tf` rather than a manual step. That keeps the no-ClickOps property
intact all the way down to the domain, and it is gated on `register_domain`,
default false.

Three properties of that resource are worth knowing before enabling it:

- **The charge is not refundable, and destroy does not undo it.** A `.com` is
  $16.00/year. Registrations cannot be cancelled, so `terraform destroy` drops
  the resource from state while the registration continues. `auto_renew`
  therefore defaults to **false** — a demo domain that renews itself every year
  is a bill nobody remembers agreeing to.
- **Nameservers must be pinned to the existing zone.** Registering through
  Route53 normally creates a fresh hosted zone and delegates to it. A zone for
  `elbeetest.com` already exists, so the default behaviour would create a
  *second* one, point the domain at it, and orphan the first along with every
  record this stack manages. `name_server` is set from the existing delegation
  set, and a variable validation refuses to plan if `register_domain` is true
  while `domain_name_servers` is empty.
- **Contact details are real.** They go to the registrar and, without privacy
  protection, into WHOIS. The variable is marked `sensitive`, all four privacy
  flags are on, and the values belong in a gitignored tfvars file — see
  `environments/dev.domain.tfvars.example`.

The Route53 Domains API exists only in `us-east-1`, so the resource uses an
aliased provider rather than assuming `var.region` happens to be that.

## Alternatives considered

**Import a self-signed certificate into ACM.** Free, and it exercises the same
ALB listener wiring — but every browser shows a warning, which makes for a
worse screenshot than plain HTTP.

**AWS Private CA.** Correct for an internal estate, roughly $400/month. Absurd
for a demo cluster.
