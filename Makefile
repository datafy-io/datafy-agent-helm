HELM_CMD := AWS_PROFILE="production" helm
URL := helm.datafy.io/datafy-agent
S3_REPO_NAME := datafyio-s3
S3_REPO_URL := s3://$(URL)
HTTP_REPO_NAME := datafyio
HTTP_REPO_URL := https://$(URL)

help:		## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n"} /^[\/0-9a-zA-Z_-]+:.*##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

lint: ## Run lint
	$(HELM_CMD) lint

template: ## Generate templates to stdout
	$(HELM_CMD) template .  --set-string "datafy.token=1"

repos: ## add dataf-agent repositories to helm
	@$(HELM_CMD) plugin list | grep -q "^s3" || (echo "installing helm s3 plugin" && helm plugin install https://github.com/hypnoglow/helm-s3.git)
	@$(HELM_CMD) repo add $(S3_REPO_NAME) $(S3_REPO_URL)
	@$(HELM_CMD) repo add $(HTTP_REPO_NAME) $(HTTP_REPO_URL)

clean: ## clean
	@rm -rf dist

build: ## build the helm package
build: clean
	@mkdir -p dist
	@$(HELM_CMD) package -d dist .

release: ## build and release the helm package to s3
release: build
	@$(HELM_CMD) repo list | grep -q "^$(S3_REPO_NAME)" || (echo "missing $(S3_REPO_NAME) repo. Please run 'make repos'" && exit 1)
	@$(HELM_CMD) s3 push dist/datafy-agent-*.tgz $(S3_REPO_NAME) --relative
