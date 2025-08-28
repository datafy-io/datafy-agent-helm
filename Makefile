REPO_NAME := datafyio
REPO_URL := https://helm.datafy.io/datafy-agent

CAPABILITIES_VALUES := -a "external-secrets.io/v1beta1/ClusterSecretStore"
DEFAULT_VALUES := --set-string "agent.token=1" --set-string "agent.image.tag=1"

help:		## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n"} /^[\/0-9a-zA-Z_-]+:.*##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

lint: ## Run lint
	helm lint $(DEFAULT_VALUES)

template: ## Generate templates to stdout
	helm template . $(DEFAULT_VALUES) $(CAPABILITIES_VALUES)

repos: ## add dataf-agent repository to helm
	helm repo add $(REPO_NAME) $(REPO_URL)

clean: ## clean
	@rm -rf dist

build: ## build the helm package
build: clean
	@mkdir -p dist
	helm package -d dist .
