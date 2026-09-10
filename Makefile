# Common workflows. ENV selects the environment; everything else follows from it.
#
#   make init ENV=dev
#   make plan ENV=dev
#   make apply ENV=dev

# Override to use a specific Terraform binary, e.g. while the system install is
# older than the >= 1.11 this repo requires:  make plan TF=/tmp/tfbin/terraform
TF ?= terraform

ENV ?= dev
TFVARS := environments/$(ENV).tfvars
BACKEND := environments/$(ENV).s3.tfbackend

.DEFAULT_GOAL := help
.PHONY: help bootstrap init plan apply destroy fmt validate check clean kubeconfig tunnel image deploy url

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Create the remote state bucket (once per AWS account)
	cd bootstrap && $(TF) init && $(TF) apply

init: ## Initialise against the $(ENV) backend
	$(TF) init -reconfigure -backend-config=$(BACKEND)

plan: ## Plan $(ENV) and write the plan to disk
	$(TF) plan -var-file=$(TFVARS) -out=$(ENV).tfplan

apply: ## Apply the saved $(ENV) plan (run `make plan` first)
	$(TF) apply $(ENV).tfplan

destroy: ## Tear down $(ENV)
	$(TF) destroy -var-file=$(TFVARS)

fmt: ## Rewrite all Terraform to canonical format
	$(TF) fmt -recursive .

validate: ## Validate configuration without touching the backend
	$(TF) init -backend=false -upgrade >/dev/null && $(TF) validate

check: ## Non-mutating checks, the same set CI runs
	$(TF) fmt -recursive -check -diff .
	$(MAKE) validate

kubeconfig: ## Point kubectl at the $(ENV) cluster
	aws eks update-kubeconfig --name $$($(TF) output -raw cluster_name) \
		--region $$($(TF) output -raw region)

image: ## Build and push the app image to ECR, tagged with the commit SHA
	@REPO=$$($(TF) output -raw ecr_repository_url); \
	SHA=$$(git rev-parse --short HEAD); \
	echo "building $$REPO:$$SHA"; \
	docker build --platform linux/amd64 -t "$$REPO:$$SHA" app; \
	aws ecr get-login-password --region $$($(TF) output -raw region) \
	  | docker login --username AWS --password-stdin "$${REPO%%/*}"; \
	docker push "$$REPO:$$SHA"; \
	DIGEST=$$(aws ecr describe-images --repository-name $$(basename $$REPO) \
	  --image-ids imageTag=$$SHA --query 'imageDetails[0].imageDigest' --output text); \
	echo "digest: $$DIGEST"; \
	cd app/k8s && kustomize edit set image hello-world=$$REPO@$$DIGEST 2>/dev/null \
	  || sed -i '' "s|digest: sha256:.*|digest: $$DIGEST|" kustomization.yaml; \
	echo "kustomization.yaml updated -- commit it, then: make deploy"

deploy: ## Apply the app manifests to the cluster
	kubectl apply -k app/k8s
	kubectl -n demo rollout status deploy/hello-world --timeout=300s

url: ## Print the public URL of the app
	@echo "http://$$(kubectl -n demo get ingress hello-world -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

tunnel: ## SSM port-forward to the cluster API on localhost:8443 (no SSH, no open ports)
	@eval "$$($(TF) output -raw tunnel_command)"

clean: ## Remove local plans and provider caches
	rm -f *.tfplan
	find . -type d -name .terraform -prune -exec rm -rf {} +
