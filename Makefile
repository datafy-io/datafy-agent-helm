REPO_NAME := datafyio
REPO_URL := https://helm.datafy.io/datafy-agent

HELM_CMD := docker run --rm -it -v ~/.kube:/root/.kube -v `pwd`:/datafy-agent-helm -w /datafy-agent-helm alpine/helm:3.18

DEFAULT_VALUES := --set-string "agent.token=1" --set-string "agent.image.tag=1"

help:		## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n"} /^[\/0-9a-zA-Z_-]+:.*##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

lint: ## Run lint
	$(HELM_CMD) lint $(DEFAULT_VALUES)

template: ## Generate templates to stdout
	$(HELM_CMD) template . $(DEFAULT_VALUES) $(CAPABILITIES_VALUES) --set validation.enabled=false

repos: ## add dataf-agent repository to helm
	$(HELM_CMD) repo add $(REPO_NAME) $(REPO_URL)

clean: ## clean
	@rm -rf dist

build: ## build the helm package
build: clean
	@mkdir -p dist
	$(HELM_CMD) package -d dist .
