# Common workflows. ENV selects the environment; everything else follows from it.
#
#   make init ENV=dev
#   make plan ENV=dev
#   make apply ENV=dev

ENV ?= dev
TFVARS := environments/$(ENV).tfvars
BACKEND := environments/$(ENV).s3.tfbackend

.DEFAULT_GOAL := help
.PHONY: help bootstrap init plan apply destroy fmt validate check clean kubeconfig

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Create the remote state bucket (once per AWS account)
	cd bootstrap && terraform init && terraform apply

init: ## Initialise against the $(ENV) backend
	terraform init -reconfigure -backend-config=$(BACKEND)

plan: ## Plan $(ENV) and write the plan to disk
	terraform plan -var-file=$(TFVARS) -out=$(ENV).tfplan

apply: ## Apply the saved $(ENV) plan (run `make plan` first)
	terraform apply $(ENV).tfplan

destroy: ## Tear down $(ENV)
	terraform destroy -var-file=$(TFVARS)

fmt: ## Rewrite all Terraform to canonical format
	terraform fmt -recursive .

validate: ## Validate configuration without touching the backend
	terraform init -backend=false -upgrade >/dev/null && terraform validate

check: ## Non-mutating checks, the same set CI runs
	terraform fmt -recursive -check -diff .
	$(MAKE) validate

kubeconfig: ## Point kubectl at the $(ENV) cluster
	aws eks update-kubeconfig --name $$(terraform output -raw cluster_name) \
		--region $$(terraform output -raw region)

clean: ## Remove local plans and provider caches
	rm -f *.tfplan
	find . -type d -name .terraform -prune -exec rm -rf {} +
