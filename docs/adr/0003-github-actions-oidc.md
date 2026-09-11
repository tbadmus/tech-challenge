# ADR-0003 — Replace Jenkins with GitHub Actions using OIDC federation

**Status:** Accepted · 2026-09-10

## Context

The existing `Jenkinsfile` has structural problems beyond its age:

- **No gate can fail the build.** `waitForQualityGate abortPipeline: false`,
  and neither Trivy invocation passes `--exit-code 1`. The `-security-checks`
  flag was renamed years ago, so on any current Trivy the step errors or scans
  nothing. Three independent security gates, all decorative.
- **Static credentials.** The pipeline relies on AWS credentials configured on
  the Jenkins host — long-lived keys, the exact thing OIDC federation exists to
  remove.
- **One state file for every branch.** `dev` and `master` both run
  `terraform apply -auto-approve` against `lb-terraform.tfstate`, so the
  feature → dev → main strategy is not implemented anywhere.
- **Ungated deployment stages.** Infrastructure is gated to `dev`/`master`, but
  the two `kubectl apply` stages are not, so a feature branch deploys to the
  shared cluster.

Jenkins could be fixed in place. But the repo already lives on GitHub, and the
single highest-value change — eliminating long-lived AWS keys — is markedly
simpler on Actions, where `aws-actions/configure-aws-credentials` exchanges a
short-lived OIDC token for a role session.

## Decision

GitHub Actions, with an IAM OIDC identity provider for
`token.actions.githubusercontent.com` and per-environment roles whose trust
policies are scoped by `sub` claim to a specific repository, branch and
environment.

- Pull request: `fmt -check`, `validate`, `tflint`, `checkov`, `plan`, with the
  plan posted as a PR comment. All blocking.
- Merge to `dev`: apply to the dev environment.
- Merge to `main`: apply to prod behind a GitHub Environment protection rule
  requiring a human approval.

The `Jenkinsfile` is kept, annotated, for one phase as a side-by-side
comparison — Jenkins is still what many engineers will meet in the field — and
then removed.

## Consequences

- No long-lived AWS access keys anywhere in the system.
- The trust policy is the security boundary. It must pin `repo:` **and**
  `ref:`; a wildcard `sub` would let any branch in any fork assume the role.
- Gates that can fail will fail, and will fail the first time they run. That is
  the point, and Phase 5 should budget for the backlog they surface.
- Loss of Jenkins' plugin ecosystem, which this project does not use.

## Alternatives considered

**Modernize Jenkins in place.** Keeps the tool an audience may recognize.
Rejected: OIDC federation is achievable but significantly more work, and the
controller itself then becomes infrastructure to maintain and patch.

**Both.** Two pipelines that must stay in step. Rejected as a maintenance trap.
