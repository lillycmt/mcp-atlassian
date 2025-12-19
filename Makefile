## ==Commands==

CODEARTIFACT_DOMAIN = cmt
CODEARTIFACT_DOMAIN_OWNER = 423031077609
CODEARTIFACT_REGION = us-east-1

AWS_ACCOUNT_ID ?= 423031077609
AWS_REGION ?= us-east-1
SERVICE_NAME ?= mcp-atlassian
SERVICE_REPO_PFX ?= service
ECR_REPO ?= $(SERVICE_REPO_PFX)/$(SERVICE_NAME)
ECR_URI = $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(ECR_REPO)
ECS_CLUSTER ?= cmt-alpha-cluster01
ECS_SERVICE ?= mcp-atlassian

# Version tag defaults to short git commit hash
SERVICE_VERSION ?= $(shell git rev-parse --short HEAD)
IMAGE_NAME = $(SERVICE_NAME):$(SERVICE_VERSION)
IMAGE_FULL_NAME = $(ECR_URI):$(SERVICE_VERSION)
# Mutable tag for easy redeployment (can be overwritten)
MUTABLE_TAG ?= latest
IMAGE_MUTABLE_NAME = $(ECR_URI):$(MUTABLE_TAG)

## container: Build the Docker image
container: auth
	@echo "🛠️  Building Docker image $(IMAGE_NAME)..."
	docker build -t $(IMAGE_NAME) .
	@echo "✅ Build complete."

## auth: create .codeartifact.secret
auth:
	@aws codeartifact get-authorization-token \
	  --domain $(CODEARTIFACT_DOMAIN) \
	  --domain-owner $(CODEARTIFACT_DOMAIN_OWNER) \
	  --region $(CODEARTIFACT_REGION) \
	  --query authorizationToken \
	  --output text >.codeartifact.secret

## docker-push: Build, tag, and push the commit-hash image to ECR
docker-push: container
	@echo "🏷️  Tagging image with commit hash $(SERVICE_VERSION)..."
	docker tag $(IMAGE_NAME) $(IMAGE_FULL_NAME)
	@echo "🏷️  Tagging image with mutable tag $(MUTABLE_TAG)..."
	docker tag $(IMAGE_NAME) $(IMAGE_MUTABLE_NAME)
	@echo "🚀 Pushing to ECR..."
	@echo "   Pushing commit hash tag (may skip if already exists)..."
	@output=$$(docker push $(IMAGE_FULL_NAME) 2>&1) || { \
		if echo "$$output" | grep -q "already exists"; then \
			echo "   ⚠️  Commit hash tag already exists, skipping..."; \
		else \
			echo "$$output"; \
			exit 1; \
		fi \
	}
	@echo "   Pushing mutable tag $(MUTABLE_TAG)..."
	docker push $(IMAGE_MUTABLE_NAME)
	@echo "✅ Successfully pushed:"
	@echo "   - $(IMAGE_FULL_NAME) (immutable, may already exist)"
	@echo "   - $(IMAGE_MUTABLE_NAME) (mutable, always updated)"

## deploy-local: Update ECS service to use the new image (manual deploy)
deploy-local: docker-push
	@if [ -z "$(ECS_CLUSTER)" ] || [ -z "$(ECS_SERVICE)" ]; then \
		echo "❌ Must set ECS_CLUSTER and ECS_SERVICE"; \
		exit 1; \
	fi
	@echo "🔄 Updating ECS service $(ECS_SERVICE)..."
	aws ecs update-service \
		--cluster $(ECS_CLUSTER) \
		--service $(ECS_SERVICE) \
		--force-new-deployment \
		--region $(AWS_REGION)
	@echo "✅ ECS service $(ECS_SERVICE) updated with latest image."

## clean: Remove local Docker image
clean:
	docker rmi -f $(IMAGE_NAME) || true

## help: Display this help message
help:
	@sed -E -n 's/^## //p' $(MAKEFILE_LIST) | sed -e 's/^/  /' -e 's/==/\\n==/g' | column -t -s ':'
