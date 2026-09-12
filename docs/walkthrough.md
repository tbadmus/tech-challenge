# Walkthrough — modernizing a 2022 EKS stack

A teaching document. It follows a real modernization from a four-year-old
repository to a working, TLS-terminated application on EKS, and it keeps the
mistakes in. The mistakes are the useful part: most of what follows was found
by something failing, not by reading carefully.

Read alongside [`architecture-review.html`](architecture-review.html) (the
original code review) and the ADRs in [`adr/`](adr/).

---

## 1. What we started with

A June 2022 repository: eleven hand-written Terraform modules, a Packer AMI, a
Jenkins pipeline, an Express hello-world, and a self-managed Elasticsearch
stack. It deployed two VPCs joined by a Transit Gateway — worker nodes in one,
a bastion in the other.

The stated goal was to keep worker nodes off the public internet. That goal is
still correct. Almost everything built to achieve it had been replaced by native
capability that did not exist, or was not mature, in 2022.

### The first question to ask of any old stack

Not "what is broken" but **"what was this protecting against, and is that still
the right way to protect against it?"**

Here the answer was no. Containment comes from *subnet routing*, not from a VPC
boundary. A node in a private subnet has no public IP and no inbound path
whether or not that subnet sits in its own VPC. The second VPC added a network
hop, about $70/month in Transit Gateway attachments, and an entire class of
problem — and bought no additional isolation.

---

## 2. The finding that mattered most

The cluster everyone believed was private had its **API server published to the
entire internet**.

`modules/eks/main.tf` set only `subnet_ids` inside `vpc_config`. AWS then
applied its defaults:

```
endpoint_public_access  = true
public_access_cidrs     = ["0.0.0.0/0"]
endpoint_private_access = false
```

IAM still gated authentication, so this was not an open cluster. But the network
posture was the exact inverse of the design intent, and nothing in the code said
so — because the code said *nothing at all*.

> **Lesson.** An unset field is a decision, and it is a decision made by
> somebody who has never seen your architecture. Read provider defaults for
> anything security-relevant. "We didn't configure it" and "it is off" are not
> the same sentence.

The modernized code cannot repeat this. `cluster_endpoint_public_access_cidrs`
carries a validation that rejects `0.0.0.0/0` outright, and a second one that
refuses to plan if public access is enabled with an empty allowlist — because
the community module's own default for an empty list is, again, `0.0.0.0/0`.

---

## 3. Gates that cannot fail are worse than no gates

The Jenkinsfile ran three security gates. Not one could fail a build.

```groovy
waitForQualityGate abortPipeline: false          // Sonar cannot fail the build
trivy fs -security-checks vuln,config app/       // no --exit-code: findings printed, ignored
trivy image node                                 // same
```

`-security-checks` was renamed to `--scanners` in Trivy v0.38 and `config`
became `misconfig`, so on any current Trivy that step errored or scanned
nothing. The gate was not merely permissive — it probably was not running.

> **Lesson.** A green tick people trust, that checks nothing, is a liability. If
> you add a scanner, make it fail the build the first time you run it, and deal
> with the backlog. If you cannot afford to do that today, do not add the
> scanner today.

When the replacement pipeline ran for the first time it failed immediately and
found **six** classes of real defect — missing version constraints in five
modules, an unused variable, two empty output files, two dead declarations, two
orphaned variables, and fourteen checkov findings. Every one had been sitting
there for four years behind a green tick.

---

## 4. Reading a plan is a skill

Two moments in this project would have cost real money if the plan had been
skimmed.

**The duplicate access entry.** `enable_cluster_creator_admin_permissions = true`
creates an EKS access entry for the caller's IAM role. That resolved to exactly
the SSO role ARN already listed in `cluster_admin_role_arns`. EKS rejects
duplicate entries — so the apply would have failed *after* creating the control
plane, an eleven-minute operation, leaving a half-built cluster.

**The tainted domain.** Registering `elbeetest.com` succeeded, but the provider
then failed its own round-trip check on an unrelated field and returned four
errors. That marked the resource **tainted**. The next plan proposed *destroying
and re-registering the domain* — a second non-refundable $16 charge for
something that cannot be un-registered. `terraform untaint` fixed it.

> **Lesson.** `terraform apply -auto-approve` on anything that spends money or
> cannot be undone is a bet you will eventually lose. Read the verbs: `create`,
> `update`, `replace`, `destroy`. Note that a *failed* apply can leave state in
> a shape that makes the *next* plan destructive.

---

## 5. Test the claim, not the configuration

ADR-0004 said operators would reach a private cluster over an SSM port-forward
instead of SSH. The configuration looked perfect: SSM host online, zero inbound
rules, no key pair, IMDSv2 required.

The tunnel opened, accepted the connection, and passed no data.

The EKS cluster security group allows 443 **only from the node security group**.
Nothing else in the VPC could reach the private endpoint — including the host
whose only purpose was to reach it.

> **Lesson.** "Configured correctly" and "works" are different claims. The only
> way to know which one you have is to run the thing. A tunnel that opens is not
> a tunnel that works.

The same pattern recurred in Phase 6. Fluent Bit was running, log groups
existed, streams appeared — and the application's own logs were nowhere,
because the app only logged on startup and shutdown. A healthy pod was
completely silent.

---

## 6. When the tooling tells you something true

Three failures in this project were the design pushing back, not bugs.

**CI could not plan the stack.** The first successful pipeline run failed with:

```
Get "https://<id>.gr7.us-east-1.eks.amazonaws.com/apis/storage.k8s.io/v1/storageclasses/gp3":
dial tcp 174.129.23.46:443: i/o timeout
```

The `kubernetes` and `helm` providers authenticate against the cluster API, so
`terraform plan` must *reach* it even to compute a diff — and a GitHub-hosted
runner is not on the allowlist. That is the allowlist working.

The answer was to split cluster software into its own root module
(`cluster-addons/`), so the infrastructure root has no cluster-facing provider
and plans from anywhere. Three live resources were migrated with `state rm` +
`import` — no downtime, the site stayed up throughout.

**The allowlist locked the operator out.** While writing this document,
`kubectl` stopped working. The operator's residential IP had rotated from
`174.196.128.110` to `96.241.165.110`, and the allowlist no longer matched.

The SSM tunnel — the fallback ADR-0004 chose precisely because allowlists are
brittle — gave full cluster access with the operator's IP nowhere on the list.
The design worked. The lesson is that it needed to.

> **Lesson.** IP allowlists on dynamic addresses are a control with a short
> half-life. Always build the path that does not depend on where you are sitting.

---

## 7. Things that look free and are not

| Looked free | Actually |
|---|---|
| `ebs_optimized = true` to satisfy a linter | ForceNew — plans a full instance replacement |
| Letting Container Insights create its log groups | Retention defaults to *Never expire*; logs bill forever |
| `applicationSignals` in the CloudWatch addon | Defaults to **on**, billed per trace and per observed service |
| Registering a domain through Route 53 | Creates a **second** hosted zone and delegates to it, orphaning yours |
| `name_server` as a list | Ordered; the provider reads it back sorted, so it diffs on every plan forever |
| Resolving the *latest* AMI from SSM | A new AMI release replaces your instance on the next unrelated apply |

Every row was found by reading a plan or a bill-shaped detail, not by intuition.

---

## 8. The shape of the result

Deleted, with what replaced it:

| Removed | Replaced by |
|---|---|
| Second VPC + Transit Gateway | Subnet routing in one VPC, 3 AZs |
| `routes.sh` in a `null_resource` | Nothing — the hop no longer exists |
| Two SSH bastions, shared key pair | One SSM host: no key, no public IP, no inbound rules |
| Internal Classic Load Balancer | Internet-facing ALB targeting pod IPs |
| `aws-auth` ConfigMap | `authentication_mode = "API"` + access entries |
| Self-managed Elasticsearch/Fluentd/Kibana | `amazon-cloudwatch-observability` addon |
| Jenkins with static AWS keys | GitHub Actions with OIDC, no long-lived credentials |
| `sed -i` on tracked manifests | Kustomize, image referenced by digest |
| `node:8.9.4` running as root | `node:22-alpine`, multi-stage, non-root, `restricted` PSS |

Net effect on the network layer alone: **−351 lines**. The replacement is
smaller than what it replaced, which is the clearest evidence the complexity
was not buying anything.

---

## 9. Exercises

For a junior engineer working through this repository:

1. **Find the default.** Open `modules/eks/main.tf` on the `master` branch. Without
   looking at the review, list every security-relevant field that is *not* set,
   and look up what AWS does with each.
2. **Break the guard.** Set `cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]`
   in a tfvars file and run `terraform plan`. Read the error. Now set it to `[]`
   and run again — a different guard fires, for a different reason.
3. **Trace the tag.** Nothing in `app/k8s/ingress.yaml` names a subnet. Work out
   how the ALB knows where to go. (Start in `network.tf`.)
4. **Watch the digest.** Change one character in `app/hello.js`, run
   `make image && make deploy`, and compare `kubectl -n demo get pods -o
   jsonpath='{.items[0].spec.containers[0].image}'` before and after. Then change
   `kustomization.yaml` to use a tag instead of a digest and do it again.
5. **Lose your access.** Set the allowlist to a CIDR that is not yours, apply,
   and get to the cluster anyway. (`make tunnel ENV=dev`.)
6. **Read a real plan.** Run `make plan ENV=dev` and find every resource that
   would be *replaced* rather than updated. For each, work out which attribute
   is ForceNew.
