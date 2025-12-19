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
TASK_FAMILY ?= cmt-alpha-mcp-atlassian

# Version tag defaults to short git commit hash
SERVICE_VERSION ?= $(shell git rev-parse --short HEAD)
IMAGE_NAME = $(SERVICE_NAME):$(SERVICE_VERSION)
IMAGE_FULL_NAME = $(ECR_URI):$(SERVICE_VERSION)
IMAGE_BASE_NAME = $(ECR_URI)

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
	@echo "✅ Successfully pushed:"
	@echo "   - $(IMAGE_FULL_NAME) (immutable, may already exist)"

## deploy-local: Update ECS task definition and service with new image (manual deploy)
## This updates the task definition to use the newly pushed image, then updates the service
deploy-local: docker-push
	@if [ -z "$(ECS_CLUSTER)" ] || [ -z "$(ECS_SERVICE)" ] || [ -z "$(TASK_FAMILY)" ]; then \
		echo "❌ Must set ECS_CLUSTER, ECS_SERVICE, and TASK_FAMILY"; \
		exit 1; \
	fi
	@echo "📥 Fetching current task definition for $(TASK_FAMILY)..."
	@aws ecs describe-task-definition \
		--task-definition $(TASK_FAMILY) \
		--region $(AWS_REGION) \
		--include TAGS \
		--query '{containerDefinitions:taskDefinition.containerDefinitions, cpu:taskDefinition.cpu, ephemeralStorage:taskDefinition.ephemeralStorage, executionRoleArn:taskDefinition.executionRoleArn, family:taskDefinition.family, inferenceAccelerators:taskDefinition.inferenceAccelerators, ipcMode:taskDefinition.ipcMode, memory:taskDefinition.memory, networkMode:taskDefinition.networkMode, pidMode:taskDefinition.pidMode, placementConstraints:taskDefinition.placementConstraints, proxyConfiguration:taskDefinition.proxyConfiguration, requiresCompatibilities:taskDefinition.requiresCompatibilities, runtimePlatform:taskDefinition.runtimePlatform, tags:tags, taskRoleArn:taskDefinition.taskRoleArn, volumes:taskDefinition.volumes}' \
		| grep -v null \
		| sed 's|$(IMAGE_BASE_NAME):[^"]*|$(IMAGE_FULL_NAME)|' > task-definition.json
	@echo "📝 Registering new task definition with image $(IMAGE_FULL_NAME)..."
	@aws ecs register-task-definition \
		--family $(TASK_FAMILY) \
		--region $(AWS_REGION) \
		--cli-input-json file://task-definition.json \
		--query taskDefinition.taskDefinitionArn \
		| xargs echo "✅ Task definition registered:"
	@echo "🔄 Updating ECS service $(ECS_SERVICE) to use new task definition..."
	@aws ecs update-service \
		--cluster $(ECS_CLUSTER) \
		--service $(ECS_SERVICE) \
		--region $(AWS_REGION) \
		--task-definition $(TASK_FAMILY) \
		--query 'service.deployments[].{id:id,status:status,createdAt:createdAt,rolloutState:rolloutState,taskDefinition:taskDefinition,runningCount:runningCount,pendingCount:pendingCount,failedTasks:failedTasks}'
	@echo "🧹 Cleaning up temporary task-definition.json..."
	@rm -f task-definition.json
	@echo "✅ Deployment initiated! Monitor with: make check-deploy"

## check-deploy: Get the service deployment status
check-deploy:
	@aws ecs describe-services \
		--cluster $(ECS_CLUSTER) \
		--services $(ECS_SERVICE) \
		--region $(AWS_REGION) \
		--include TAGS \
		--query 'services[0].deployments[].{id:id,status:status,createdAt:createdAt,rolloutState:rolloutState,taskDefinition:taskDefinition,runningCount:runningCount,pendingCount:pendingCount,failedTasks:failedTasks}'

## clean: Remove local Docker image and temporary files
clean:
	docker rmi -f $(IMAGE_NAME) || true
	rm -f task-definition.json .codeartifact.secret || true

## help: Display this help message
help:
	@sed -E -n 's/^## //p' $(MAKEFILE_LIST) | sed -e 's/^/  /' -e 's/==/\\n==/g' | column -t -s ':'
