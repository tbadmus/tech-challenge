# Optional — the original Jenkins pipeline

Superseded by `.github/workflows/` per ADR-0003. Kept because Jenkins is still
what many engineers meet in the field, and because reading the two side by side
is the clearest way to see what changed and why.

**Nothing here is wired to anything.** It is reading material. `sonar-project.properties`
sits alongside the Jenkinsfile for the same reason: it configured a scanner that
only the Jenkins pipeline ever invoked, and it pointed at `sonar.sources=app` --
a ten-line JavaScript file -- while the Terraform, where the real exposure was,
went unexamined.

## What was wrong with it

### Every security gate was decorative

Three independent gates, none of which could fail a build:

```groovy
waitForQualityGate abortPipeline: false        // Sonar can never fail the build
trivy fs -security-checks vuln,config app/     // no --exit-code, so findings are printed and ignored
trivy image node                               // same
```

`-security-checks` was renamed to `--scanners` in Trivy v0.38, and `config`
became `misconfig`. On any current Trivy that step errors or scans nothing —
so the gate was not merely permissive, it was probably not running.

A gate that cannot fail is worse than no gate: it produces a green tick that
means nothing, and people trust green ticks.

### Static AWS credentials

The pipeline relied on credentials configured on the Jenkins host — long-lived
access keys, the exact thing OIDC federation exists to remove. The replacement
mints a short-lived token per job and exchanges it for a role session, scoped by
a trust policy that pins the repository and the ref or environment.

### One state file for every branch

`terraform apply -auto-approve` ran on both `dev` and `master` against a single
hardcoded state key, so the branching strategy existed on paper only. Both
branches mutated the same real infrastructure, and two concurrent builds could
corrupt state.

### Ungated deployment stages

Infrastructure was gated to `dev`/`master`:

```groovy
when { expression { return env.BRANCH_NAME in environment_branches } }
```

but `Deploy logging` and `Deploy application in K8S` carried no such gate, so a
feature branch build deployed straight to the shared cluster. The application
stage also depended on the kubeconfig written by the *logging* stage — an
ordering coupling that breaks the moment either is reordered or skipped.

### A credential written into tracked files

```groovy
sed -i -e "s%ELASTIC-PASSWORD%${ELASTIC}%g" logging/elastic.yaml
```

The Elasticsearch password ended up in plaintext in the workspace, in the
applied pod spec, and in anything archiving the workspace. Jenkins masks
credentials in console output; it does not mask them on disk.

### `|| true`

```groovy
aws ec2 import-key-pair --key-name mvp ... || true
```

Intended for idempotency, but it swallows every failure — permissions, quota,
malformed key — indistinguishably from "already exists".

### Unconditional Packer builds

`packer build` ran on every execution and named the AMI with `isotime`, so each
run produced a new AMI. Terraform's `data.aws_ami` used `most_recent = true`,
so the bastion instance was destroyed and recreated on every single pipeline
run, with AMIs and snapshots accumulating forever.

## What replaced it

| Concern | Jenkinsfile | `.github/workflows/` |
|---|---|---|
| AWS auth | static keys on the controller | OIDC, short-lived, trust policy pinned to repo + ref/environment |
| Sonar / Trivy | cannot fail the build | blocking, `exit-code: 1`, correct `--scanners` flags |
| IaC checks | none | `fmt -check`, `validate`, tflint, checkov — all blocking |
| Plan visibility | buried in console output | posted and updated as a PR comment |
| State | one key, all branches | per-environment backend config, S3 native locking |
| Prod apply | `-auto-approve` on push | blocked on a required reviewer, plus an AWS trust policy that only accepts `environment:prod` |
| Image reference | implicit `:latest`, mutable repo | commit SHA then deployed by digest, immutable repo |
| Manifests | `sed -i` on tracked files | Kustomize image transformer |
| Secrets | `sed` into YAML on disk | none in the pipeline |
