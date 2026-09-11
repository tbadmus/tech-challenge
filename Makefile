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

# owner/name from the origin remote, so a fork never creates IAM roles that
# trust the upstream repository.
# NOTE: '#' starts a comment in a Makefile and '@' appears in the SSH remote,
# so the sed delimiter is a comma.
GH_REPO  = $(shell git remote get-url origin 2>/dev/null | sed -e 's,^git@github.com:,,' -e 's,^https://github.com/,,' -e 's,\.git$$,,')

TFVAR_ARGS = -var-file=$(TFVARS) -var=github_repository=$(GH_REPO)

.DEFAULT_GOAL := help
.PHONY: help preflight backend init plan apply up down destroy fmt validate check clean \
        addons-init addons-plan addons-apply addons-destroy \
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
	@if aws s3api head-bucket --bucket $(BUCKET) >/dev/null 2>&1; then \
	  echo "  state bucket exists: $(BUCKET)"; \
	else \
	  echo "  state bucket missing — creating it with bootstrap/"; \
	  cd bootstrap && $(TF) init -input=false >/dev/null && \
	    $(TF) apply -input=false -auto-approve \
	      -var=project=$(PROJECT_D) -var=region=$(REGION) >/dev/null && \
	    echo "  created $(BUCKET)"; \
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

init: backend ## Initialise against the $(ENV) backend
	$(TF) init -input=false -reconfigure -backend-config=$(BACKEND)

plan: ## Plan $(ENV) and save the plan to disk
	$(TF) plan -input=false $(TFVAR_ARGS) -out=$(ENV).tfplan

apply: ## Apply the saved $(ENV) plan (run `make plan` first)
	$(TF) apply -input=false $(ENV).tfplan
	@rm -f $(ENV).tfplan

destroy: ## Destroy the infrastructure root only
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
deploy: ## Deploy the application by digest
	@IMG=$$(cat .backend/$(ENV).image 2>/dev/null) || { echo "run 'make image' first"; exit 1; }; \
	TMP=$$(mktemp -d); cp -R app/k8s "$$TMP/"; \
	(cd "$$TMP/k8s" && kustomize edit set image "hello-world=$$IMG" 2>/dev/null \
	   || sed -i.bak "s|newName:.*|newName: $${IMG%@*}|; s|digest:.*|digest: $${IMG#*@}|" kustomization.yaml); \
	kubectl apply -k "$$TMP/k8s"; rm -rf "$$TMP"; \
	kubectl -n demo rollout status deploy/hello-world --timeout=300s

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
	@echo "==> 6/6 deploy"       && $(MAKE) --no-print-directory deploy ENV=$(ENV)
	@echo ""
	@echo "  done: $$($(MAKE) --no-print-directory url ENV=$(ENV))"

_confirm:
	@printf "  apply the plan above? [y/N] " && read a && [ "$$a" = "y" ]

down: ## Tear everything down, in the order that actually works
	@echo "==> 1/3 application" && kubectl delete -k app/k8s --ignore-not-found=true || true
	@echo "==> 2/3 cluster software" && $(MAKE) --no-print-directory addons-destroy ENV=$(ENV) || true
	@echo "==> 3/3 infrastructure" && $(MAKE) --no-print-directory destroy ENV=$(ENV)

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
