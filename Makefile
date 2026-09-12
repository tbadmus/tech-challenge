# tech-challenge — deployable into any AWS account with no file edits.
#
# Everything account-specific is DERIVED, not configured:
#   account id        <- aws sts get-caller-identity
#   state bucket      <- <project>-tfstate-<account-id>, created if absent
#   github repository <- git remote get-url origin
#   region / project  <- environments/<env>.tfvars
#
#   make up ENV=dev        one command, all stages, gated on readiness
#   make down ENV=dev      teardown in the correct order
#   make help              everything else

TF  ?= terraform
ENV ?= dev

TFVARS  := environments/$(ENV).tfvars
BACKEND := .backend/$(ENV).infra.hcl
ADDONS_BACKEND := .backend/$(ENV).addons.hcl

# Lazy (=) not immediate (:=) so `make help` does not pay for an STS call.
ACCOUNT  = $(shell aws sts get-caller-identity --query Account --output text)
REGION   = $(shell awk -F'"' '/^[[:space:]]*region[[:space:]]*=/{print $$2; exit}' $(TFVARS))
PROJECT  = $(shell awk -F'"' '/^[[:space:]]*project[[:space:]]*=/{print $$2; exit}' $(TFVARS) 2>/dev/null || true)
PROJECT_D = $(if $(PROJECT),$(PROJECT),tech-challenge)
BUCKET   = $(PROJECT_D)-tfstate-$(ACCOUNT)

# Derived, not read from `terraform output cluster_name`. During a teardown the
# output disappears the moment the cluster leaves state, and the teardown
# targets need the name AFTER that point.
CLUSTER  = $(PROJECT_D)-$(ENV)-cluster

# Everything the load balancer controller creates carries this tag. It is what
# makes the teardown targets safe to point at a VPC: they never touch a load
# balancer somebody created by hand alongside the cluster.
LB_TAG   = elbv2.k8s.aws/cluster

# owner/name from the origin remote, so a fork never creates IAM roles that
# trust the upstream repository.
# NOTE: '#' starts a comment in a Makefile and '@' appears in the SSH remote,
# so the sed delimiter is a comma.
GH_REPO  = $(shell git remote get-url origin 2>/dev/null | sed -e 's,^git@github.com:,,' -e 's,^https://github.com/,,' -e 's,\.git$$,,')

TFVAR_ARGS = -var-file=$(TFVARS)

.DEFAULT_GOAL := help
.PHONY: help preflight bootstrap ci-secrets backend init plan apply up down destroy fmt validate check clean \
        addons-init addons-plan addons-apply addons-destroy \
        lb-orphans wait-lb-gone lb-orphans-delete \
        image deploy deploy-tls url kubeconfig tunnel wait-cluster wait-nodes wait-controller

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  ENV=$(ENV)  (override with ENV=prod)"

# ---------------------------------------------------------------------------
# Preflight and backend
# ---------------------------------------------------------------------------

preflight: ## Check credentials, tools, and derived values
	@command -v $(TF) >/dev/null || { echo "terraform not found"; exit 1; }
	@command -v aws  >/dev/null || { echo "aws cli not found"; exit 1; }
	@test -f $(TFVARS) || { echo "missing $(TFVARS)"; exit 1; }
	@aws sts get-caller-identity >/dev/null 2>&1 || { \
	  echo "not authenticated — run: aws sso login --profile <profile> && export AWS_PROFILE=<profile>"; exit 1; }
	@test -n "$(GH_REPO)" || echo "  warning: no git origin remote; set TF_VAR_github_repository or enable_github_oidc=false"
	@echo "  account    $(ACCOUNT)"
	@echo "  region     $(REGION)"
	@echo "  bucket     $(BUCKET)"
	@echo "  repository $(GH_REPO)"

backend: preflight ## Ensure the state bucket exists, then generate backend config
	@# head-bucket distinguishes three outcomes, and conflating them is a trap:
	@#   exit 0  -> exists and readable
	@#   404     -> does not exist, safe to create
	@#   403     -> EXISTS but this principal cannot see it. Treating that as
	@#              "missing" makes Terraform try to create a bucket that is
	@#              already there, which fails confusingly several errors deep.
	@#              Almost always the wrong role, so say so.
	@ERR=$$(aws s3api head-bucket --bucket $(BUCKET) 2>&1); RC=$$?; \
	if [ $$RC -eq 0 ]; then \
	  echo "  state bucket exists: $(BUCKET)"; \
	elif echo "$$ERR" | grep -q '403\|Forbidden'; then \
	  echo ""; \
	  echo "  The state bucket $(BUCKET) EXISTS but this identity cannot read it:"; \
	  echo "    $$(aws sts get-caller-identity --query Arn --output text)"; \
	  echo ""; \
	  echo "  This is a permissions problem, not a missing bucket. Re-authenticate"; \
	  echo "  with a permission set that has S3 access to it."; \
	  exit 1; \
	elif echo "$$ERR" | grep -q '404\|Not Found'; then \
	  echo "  state bucket missing — creating it with bootstrap/"; \
	  cd bootstrap && $(TF) init -input=false >/dev/null && \
	    $(TF) apply -input=false -auto-approve \
	      -var=project=$(PROJECT_D) -var=region=$(REGION) \
	      -var=github_repository=$(GH_REPO) >/dev/null && \
	    echo "  created $(BUCKET)"; \
	else \
	  echo "  could not determine whether $(BUCKET) exists:"; echo "$$ERR" | head -3; exit 1; \
	fi
	@mkdir -p .backend
	@printf 'bucket       = "%s"\nkey          = "%s/terraform.tfstate"\nregion       = "%s"\nencrypt      = true\nuse_lockfile = true\n' \
	  "$(BUCKET)" "$(ENV)" "$(REGION)" > $(BACKEND)
	@printf 'bucket       = "%s"\nkey          = "%s/cluster-addons.tfstate"\nregion       = "%s"\nencrypt      = true\nuse_lockfile = true\n' \
	  "$(BUCKET)" "$(ENV)" "$(REGION)" > $(ADDONS_BACKEND)
	@echo "  backend config written to .backend/"

# ---------------------------------------------------------------------------
# Infrastructure root
# ---------------------------------------------------------------------------

bootstrap: preflight ## Apply the bootstrap root: state bucket and CI identity
	cd bootstrap && $(TF) init -input=false && \
	  $(TF) apply -input=false \
	    -var=project=$(PROJECT_D) -var=region=$(REGION) -var=github_repository=$(GH_REPO)
	@echo ""
	@echo "  CI role ARNs — set these as repository secrets:"
	@cd bootstrap && printf '    AWS_PLAN_ROLE_ARN  %s\n' "$$($(TF) output -raw github_actions_plan_role_arn)"
	@cd bootstrap && printf '    AWS_APPLY_ROLE_ARN %s\n' "$$($(TF) output -raw github_actions_apply_role_arn)"

ci-secrets: ## Push the CI role ARNs to GitHub as repository secrets
	@cd bootstrap && \
	  gh secret set AWS_PLAN_ROLE_ARN  --repo $(GH_REPO) --body "$$($(TF) output -raw github_actions_plan_role_arn)" && \
	  gh secret set AWS_APPLY_ROLE_ARN --repo $(GH_REPO) --body "$$($(TF) output -raw github_actions_apply_role_arn)"
	@echo "  secrets updated on $(GH_REPO)"

init: backend ## Initialise against the $(ENV) backend
	$(TF) init -input=false -reconfigure -backend-config=$(BACKEND)

plan: ## Plan $(ENV) and save the plan to disk
	$(TF) plan -input=false $(TFVAR_ARGS) -out=$(ENV).tfplan

apply: ## Apply the saved $(ENV) plan (run `make plan` first)
	$(TF) apply -input=false $(ENV).tfplan
	@rm -f $(ENV).tfplan

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------
# The load balancer controller creates an ALB, a target group and two security
# groups in response to an Ingress. Terraform never sees any of them, so there
# is no edge in its graph from those resources to the VPC: `terraform destroy`
# deletes the cluster quite happily and then fails on the subnets, which still
# hold the ALB's network interfaces.
#
# Retrying does not help, and this is the part that makes the ordering matter
# rather than merely being tidy. The controller that would have removed the ALB
# went away with the cluster, so by the time the error appears nothing is left
# that knows how to clean up -- the ALB is orphaned and only the CLI can clear
# it. Hit for real on 2026-09-12 by running `make destroy` directly.

# Resolved from the Name tag, NOT from `terraform output vpc_id`. A partial
# destroy strips the outputs out of state -- verified: after the failed teardown
# on 2026-09-12, `terraform output` reported "No outputs found" while the VPC
# itself was still very much there. An output is unavailable in precisely the
# situation these targets exist to handle.
VPC_FILTER = "Name=tag:Name,Values=$(PROJECT_D)-$(ENV)-vpc"

lb-orphans: ## List load balancers the in-cluster controller owns (Terraform cannot see them)
	@VPC=$$(aws ec2 describe-vpcs --region $(REGION) --filters $(VPC_FILTER) \
	         --query 'Vpcs[0].VpcId' --output text 2>/dev/null); \
	[ -n "$$VPC" ] && [ "$$VPC" != "None" ] || exit 0; \
	for arn in $$(aws elbv2 describe-load-balancers --region $(REGION) \
	      --query "LoadBalancers[?VpcId=='$$VPC'].LoadBalancerArn" --output text 2>/dev/null); do \
	  aws elbv2 describe-tags --region $(REGION) --resource-arns "$$arn" \
	    --query "TagDescriptions[0].Tags[?Key=='$(LB_TAG)'].Value" --output text 2>/dev/null \
	    | grep -q . && echo "$$arn"; \
	done; true

wait-lb-gone: ## Block until the controller has released its load balancers
	@echo "  waiting for the load balancer controller to release its AWS resources"
	@for i in $$(seq 1 60); do \
	  N=$$($(MAKE) -s lb-orphans ENV=$(ENV) | grep -c . || true); \
	  [ "$$N" = "0" ] && { echo "  released"; exit 0; }; \
	  sleep 10; \
	done; \
	echo "  still present after 10 minutes -- see: make lb-orphans ENV=$(ENV)"; exit 1

lb-orphans-delete: ## Delete orphaned controller resources (recovery, only when the cluster is gone)
	@if aws eks describe-cluster --name $(CLUSTER) --region $(REGION) >/dev/null 2>&1; then \
	  echo "  The cluster still exists. Delete the Ingress and let the controller do"; \
	  echo "  it properly -- it also removes the target groups and security groups,"; \
	  echo "  which deleting the load balancer directly does not:"; \
	  echo "      make down ENV=$(ENV)"; \
	  exit 1; \
	fi
	@VPC=$$(aws ec2 describe-vpcs --region $(REGION) --filters $(VPC_FILTER) \
	         --query 'Vpcs[0].VpcId' --output text 2>/dev/null); \
	[ -n "$$VPC" ] && [ "$$VPC" != "None" ] || { echo "  no VPC found; nothing to clean"; exit 0; }; \
	FAIL=0; \
	for arn in $$($(MAKE) -s lb-orphans ENV=$(ENV)); do \
	  echo "  deleting load balancer $${arn##*:loadbalancer/}"; \
	  aws elbv2 delete-load-balancer --region $(REGION) --load-balancer-arn "$$arn" || FAIL=1; \
	  aws elbv2 wait load-balancers-deleted --region $(REGION) --load-balancer-arns "$$arn" || FAIL=1; \
	done; \
	for tg in $$(aws elbv2 describe-target-groups --region $(REGION) \
	      --query "TargetGroups[?VpcId=='$$VPC'].TargetGroupArn" --output text 2>/dev/null); do \
	  aws elbv2 describe-tags --region $(REGION) --resource-arns "$$tg" \
	    --query "TagDescriptions[0].Tags[?Key=='$(LB_TAG)'].Value" --output text 2>/dev/null \
	    | grep -q . || continue; \
	  echo "  deleting target group $${tg##*:targetgroup/}"; \
	  OK=0; \
	  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do \
	    if aws elbv2 delete-target-group --region $(REGION) --target-group-arn "$$tg" 2>/dev/null; then OK=1; break; fi; \
	    sleep 10; \
	  done; \
	  [ "$$OK" = "1" ] || { echo "    still in use after two minutes"; FAIL=1; }; \
	done; \
	for sg in $$(aws ec2 describe-security-groups --region $(REGION) \
	      --filters "Name=vpc-id,Values=$$VPC" "Name=tag-key,Values=$(LB_TAG)" \
	      --query 'SecurityGroups[].GroupId' --output text 2>/dev/null); do \
	  echo "  deleting security group $$sg"; \
	  OK=0; \
	  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do \
	    if aws ec2 delete-security-group --region $(REGION) --group-id "$$sg" 2>/dev/null; then OK=1; break; fi; \
	    sleep 10; \
	  done; \
	  [ "$$OK" = "1" ] || { echo "    still in use after two minutes"; FAIL=1; }; \
	done; \
	if [ "$$FAIL" != "0" ]; then \
	  echo ""; \
	  echo "  Some resources could not be removed. Deletion here is ASYNCHRONOUS --"; \
	  echo "  a target group stays in use until its listener is really gone, and a"; \
	  echo "  security group until its last ENI detaches. Wait a minute and re-run."; \
	  exit 1; \
	fi; \
	echo "  orphaned controller resources removed"

destroy: ## Destroy the infrastructure root only (prefer `make down`)
	@ORPHANS=$$($(MAKE) -s lb-orphans ENV=$(ENV)); \
	if [ -n "$$ORPHANS" ]; then \
	  echo ""; \
	  echo "  Refusing to destroy. The load balancer controller owns AWS resources"; \
	  echo "  in this VPC that Terraform cannot see:"; \
	  echo "$$ORPHANS" | sed 's|^.*:loadbalancer/|    |'; \
	  echo ""; \
	  echo "  Destroying now would delete the cluster, then fail on the subnets that"; \
	  echo "  still hold this load balancer's ENIs -- and the controller that would"; \
	  echo "  have removed it would be gone, so the failure is not recoverable by"; \
	  echo "  retrying."; \
	  echo ""; \
	  if aws eks describe-cluster --name $(CLUSTER) --region $(REGION) >/dev/null 2>&1; then \
	    echo "      make down ENV=$(ENV)          # the cluster is up: let the controller clean up"; \
	  else \
	    echo "      make lb-orphans-delete ENV=$(ENV)   # the cluster is already gone"; \
	  fi; \
	  echo ""; \
	  exit 1; \
	fi
	$(TF) destroy $(TFVAR_ARGS)

# ---------------------------------------------------------------------------
# Cluster software root
# ---------------------------------------------------------------------------

ADDONS_VARS = -var=region=$(REGION) -var=state_bucket=$(BUCKET) -var=infra_state_key=$(ENV)/terraform.tfstate

addons-init: backend ## Initialise the cluster-addons root
	cd cluster-addons && $(TF) init -input=false -reconfigure -backend-config=../$(ADDONS_BACKEND)

addons-plan: ## Plan cluster software (needs cluster API reach — see `make tunnel`)
	cd cluster-addons && $(TF) plan -input=false $(ADDONS_VARS)

addons-apply: ## Apply cluster software
	cd cluster-addons && $(TF) apply -input=false -auto-approve $(ADDONS_VARS)

addons-destroy: ## Destroy cluster software
	cd cluster-addons && $(TF) destroy -auto-approve $(ADDONS_VARS)

# ---------------------------------------------------------------------------
# Readiness gates. These are what make one-command orchestration reliable
# rather than intermittently flaky -- each stage has a precondition that is not
# satisfied merely because the previous `apply` returned zero.
# ---------------------------------------------------------------------------

wait-cluster: ## Block until the EKS cluster reports ACTIVE
	@C=$$($(TF) output -raw cluster_name); \
	echo "  waiting for cluster $$C to become ACTIVE"; \
	for i in $$(seq 1 60); do \
	  S=$$(aws eks describe-cluster --name $$C --region $(REGION) --query cluster.status --output text 2>/dev/null); \
	  [ "$$S" = "ACTIVE" ] && { echo "  cluster ACTIVE"; exit 0; }; \
	  [ "$$S" = "FAILED" ] && { echo "  cluster FAILED"; exit 1; }; \
	  sleep 20; \
	done; echo "  timed out waiting for cluster"; exit 1

wait-nodes: kubeconfig ## Block until at least one node is Ready
	@echo "  waiting for nodes to become Ready"
	@kubectl wait --for=condition=Ready nodes --all --timeout=600s >/dev/null 2>&1 \
	  && echo "  nodes Ready: $$(kubectl get nodes --no-headers | grep -c ' Ready ')" \
	  || { echo "  nodes did not become Ready"; kubectl get nodes; exit 1; }

wait-controller: ## Block until the load balancer controller is serving
	@echo "  waiting for the load balancer controller webhook"
	@kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=300s >/dev/null \
	  && echo "  controller ready" || { echo "  controller not ready"; exit 1; }

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

image: ## Build, push to ECR by commit SHA, and record the digest
	@REPO=$$($(TF) output -raw ecr_repository_url); \
	SHA=$$(git rev-parse --short HEAD); \
	echo "  building $$REPO:$$SHA"; \
	docker build --platform linux/amd64 -t "$$REPO:$$SHA" app; \
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin "$${REPO%%/*}" >/dev/null; \
	docker push "$$REPO:$$SHA" >/dev/null; \
	DIGEST=$$(aws ecr describe-images --repository-name $$(basename $$REPO) --region $(REGION) \
	  --image-ids imageTag=$$SHA --query 'imageDetails[0].imageDigest' --output text); \
	mkdir -p .backend && printf '%s@%s\n' "$$REPO" "$$DIGEST" > .backend/$(ENV).image; \
	echo "  pushed $$REPO@$$DIGEST"

# Renders into a temp directory rather than editing the tracked kustomization,
# so the manifests in git stay free of any account's registry hostname.
# The kustomize image key is the FULL placeholder, not "hello-world".
#
# Kustomize matches an images: entry against the whole name component of the
# reference it finds. deployment.yaml carries
# "SET-BY-MAKE-DEPLOY/hello-world", and the key "hello-world" does NOT match
# it -- the transform then does nothing AND SAYS NOTHING, so the placeholder
# reaches the cluster and the first symptom is ImagePullBackOff surfacing five
# minutes later as "timed out waiting for the condition", which names neither
# the image nor the substitution that never happened.
IMAGE_PLACEHOLDER = SET-BY-MAKE-DEPLOY/hello-world

# Renders a kustomize overlay into $$TMP with the digest injected, then REFUSES
# to apply anything that still mentions the placeholder.
#
# The assertion is the important half. Both ways of setting the image fail
# silently when they fail: `kustomize edit` exits 0 after matching nothing, and
# the `sed` this replaces targeted newName:/digest: lines that do not exist in
# a kustomization.yaml with no images: block -- so it rewrote nothing, exited
# 0, and the caller could not tell. Rendering and checking the OUTPUT is the
# only step here that cannot lie.
#
# $(1) is the overlay directory under $$TMP to render.
define render_and_verify
	if command -v kustomize >/dev/null 2>&1; then \
	  (cd "$$TMP/k8s" && kustomize edit set image "$(IMAGE_PLACEHOLDER)=$$IMG"); \
	else \
	  printf 'images:\n  - name: %s\n    newName: %s\n    digest: %s\n' \
	    "$(IMAGE_PLACEHOLDER)" "$${IMG%@*}" "$${IMG#*@}" >> "$$TMP/k8s/kustomization.yaml"; \
	fi; \
	if kubectl kustomize "$$TMP/$(1)" | grep -q "$(IMAGE_PLACEHOLDER)"; then \
	  echo "  the image placeholder survived rendering -- refusing to apply"; \
	  echo "  expected the digest from .backend/$(ENV).image: $$IMG"; \
	  rm -rf "$$TMP"; exit 1; \
	fi;
endef

deploy: ## Deploy the application by digest
	@IMG=$$(cat .backend/$(ENV).image 2>/dev/null) || { echo "run 'make image' first"; exit 1; }; \
	TMP=$$(mktemp -d); cp -R app/k8s "$$TMP/"; \
	$(call render_and_verify,k8s) \
	kubectl apply -k "$$TMP/k8s"; rm -rf "$$TMP"; \
	kubectl -n demo rollout status deploy/hello-world --timeout=300s

# Same temp-render approach as `deploy`, plus the certificate ARN and hostname
# injected from Terraform outputs -- so the tracked manifests carry no account
# id and no environment-specific hostname.
deploy-tls: ## Deploy the application over HTTPS (requires enable_dns and a resolvable domain)
	@IMG=$$(cat .backend/$(ENV).image 2>/dev/null) || { echo "run 'make image' first"; exit 1; }; \
	CERT=$$($(TF) output -raw app_certificate_arn 2>/dev/null); \
	FQDN=$$($(TF) output -raw app_fqdn 2>/dev/null); \
	if [ -z "$$CERT" ] || [ -z "$$FQDN" ]; then \
	  echo "enable_dns is off, or the certificate is not issued yet -- see dns.tf"; exit 1; fi; \
	TMP=$$(mktemp -d); cp -R app/k8s app/k8s-tls "$$TMP"/; \
	sed -i.bak -e "s|CERT_ARN_PLACEHOLDER|$$CERT|" -e "s|FQDN_PLACEHOLDER|$$FQDN|" "$$TMP/k8s-tls/ingress-tls.yaml"; \
	$(call render_and_verify,k8s-tls) \
	kubectl apply -k "$$TMP/k8s-tls"; rm -rf "$$TMP"; \
	kubectl -n demo rollout status deploy/hello-world --timeout=300s; \
	echo "  https://$$FQDN"

url: ## Print the public URL of the application
	@H=$$(kubectl -n demo get ingress hello-world -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	F=$$($(TF) output -raw app_fqdn 2>/dev/null); \
	if [ -n "$$F" ]; then echo "https://$$F"; elif [ -n "$$H" ]; then echo "http://$$H"; else echo "not deployed"; fi

# ---------------------------------------------------------------------------
# One command
# ---------------------------------------------------------------------------

up: ## Deploy everything: backend, infra, cluster software, application
	@echo "==> 1/6 backend"      && $(MAKE) --no-print-directory backend ENV=$(ENV)
	@echo "==> 2/6 infrastructure" && $(MAKE) --no-print-directory init ENV=$(ENV) \
	  && $(MAKE) --no-print-directory plan ENV=$(ENV) \
	  && $(if $(CONFIRM),,$(MAKE) --no-print-directory _confirm &&) $(MAKE) --no-print-directory apply ENV=$(ENV)
	@echo "==> 3/6 cluster readiness" && $(MAKE) --no-print-directory wait-cluster ENV=$(ENV) \
	  && $(MAKE) --no-print-directory wait-nodes ENV=$(ENV)
	@echo "==> 4/6 cluster software" && $(MAKE) --no-print-directory addons-init ENV=$(ENV) \
	  && $(MAKE) --no-print-directory addons-apply ENV=$(ENV) \
	  && $(MAKE) --no-print-directory wait-controller ENV=$(ENV)
	@echo "==> 5/6 application image" && $(MAKE) --no-print-directory image ENV=$(ENV)
	@echo "==> 6/6 deploy" && \
	  if [ -n "$$($(TF) output -raw app_fqdn 2>/dev/null)" ]; then \
	    echo "  enable_dns is on -- deploying over HTTPS"; \
	    $(MAKE) --no-print-directory deploy-tls ENV=$(ENV); \
	  else \
	    $(MAKE) --no-print-directory deploy ENV=$(ENV); \
	  fi
	@echo ""
	@echo "  done: $$($(MAKE) --no-print-directory url ENV=$(ENV))"

_confirm:
	@printf "  apply the plan above? [y/N] " && read a && [ "$$a" = "y" ]

# Note what `down` does NOT touch: the bootstrap root. The state bucket and the
# CI identity live there precisely so a routine teardown cannot remove them --
# CI has to survive in order to rebuild what it just destroyed.
down: ## Tear everything down, in the order that actually works
	@echo "==> 1/4 application"
	@if aws eks describe-cluster --name $(CLUSTER) --region $(REGION) >/dev/null 2>&1; then \
	  kubectl delete -k app/k8s --ignore-not-found=true; \
	else \
	  echo "  cluster already gone -- skipping"; \
	fi
	@echo "==> 2/4 waiting for AWS resources the controller owns"
	@$(MAKE) --no-print-directory wait-lb-gone ENV=$(ENV)
	@echo "==> 3/4 cluster software"
	@$(MAKE) --no-print-directory addons-destroy ENV=$(ENV) || true
	@echo "==> 4/4 infrastructure"
	@$(MAKE) --no-print-directory destroy ENV=$(ENV)

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

kubeconfig: ## Point kubectl at the cluster
	@aws eks update-kubeconfig --name $$($(TF) output -raw cluster_name) --region $(REGION) >/dev/null
	@echo "  kubeconfig updated"

tunnel: ## SSM port-forward to the cluster API on localhost:8443
	@eval "$$($(TF) output -raw tunnel_command)"

fmt: ## Rewrite all Terraform to canonical format
	$(TF) fmt -recursive .

validate: ## Validate configuration without touching the backend
	$(TF) init -backend=false -upgrade >/dev/null && $(TF) validate

check: ## Non-mutating checks, the same set CI runs
	$(TF) fmt -recursive -check -diff .
	@$(MAKE) --no-print-directory validate

clean: ## Remove local plans, generated backend config, and provider caches
	rm -f *.tfplan && rm -rf .backend
	find . -type d -name .terraform -prune -exec rm -rf {} +
