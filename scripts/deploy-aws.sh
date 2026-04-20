#!/usr/bin/env bash
#
# deploy-aws.sh — Deploy (or update) a preview environment on AWS ECS.
#
# Required env vars:
#   PR_NUMBER      Pull request number (e.g. 1234)
#   IMAGE_TAG      Fully qualified image reference, e.g.
#                  123456789012.dkr.ecr.us-east-1.amazonaws.com/app:pr-1234
#   CLUSTER_NAME   ECS cluster name (default: previews)
#   AWS_REGION     AWS region (default: us-east-1)
#   TASK_ROLE_ARN  IAM role ARN the task assumes
#   EXEC_ROLE_ARN  IAM role ARN ECS uses to pull the image / write logs
#   SUBNETS        Comma-separated private subnet IDs for the ENI
#   SECURITY_GROUPS Comma-separated security group IDs for the ENI
#   CONTAINER_PORT Port the container listens on (default: 3000)
#   PREVIEW_DOMAIN Base preview domain (default: preview.example.com)
#
# Outputs (stdout):
#   preview_url=<https url the ALB routes to this service>
#
# The script registers a new task definition, creates or updates the service,
# and blocks until ECS reports the service as stable.

set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${TASK_ROLE_ARN:?TASK_ROLE_ARN is required}"
: "${EXEC_ROLE_ARN:?EXEC_ROLE_ARN is required}"
: "${SUBNETS:?SUBNETS (comma-separated subnet ids) is required}"
: "${SECURITY_GROUPS:?SECURITY_GROUPS (comma-separated sg ids) is required}"

CLUSTER_NAME="${CLUSTER_NAME:-previews}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CONTAINER_PORT="${CONTAINER_PORT:-3000}"
PREVIEW_DOMAIN="${PREVIEW_DOMAIN:-preview.example.com}"

FAMILY="preview-pr-${PR_NUMBER}"
SERVICE_NAME="preview-pr-${PR_NUMBER}"
LOG_GROUP="/ecs/${FAMILY}"

echo ">> Ensuring CloudWatch log group ${LOG_GROUP} exists"
aws logs create-log-group \
  --log-group-name "${LOG_GROUP}" \
  --region "${AWS_REGION}" 2>/dev/null || true

echo ">> Registering task definition ${FAMILY}"
TASK_DEF_JSON=$(cat <<JSON
{
  "family": "${FAMILY}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "${EXEC_ROLE_ARN}",
  "taskRoleArn": "${TASK_ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "${IMAGE_TAG}",
      "essential": true,
      "portMappings": [
        { "containerPort": ${CONTAINER_PORT}, "protocol": "tcp" }
      ],
      "environment": [
        { "name": "NODE_ENV", "value": "production" },
        { "name": "PR_NUMBER", "value": "${PR_NUMBER}" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${LOG_GROUP}",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
JSON
)

TASK_DEF_ARN=$(aws ecs register-task-definition \
  --region "${AWS_REGION}" \
  --cli-input-json "${TASK_DEF_JSON}" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo ">> Registered ${TASK_DEF_ARN}"

# Build the awsvpc network configuration from the comma-separated inputs.
NETWORK_CONFIG=$(cat <<JSON
{
  "awsvpcConfiguration": {
    "subnets": [$(echo "\"${SUBNETS}\"" | sed 's/,/","/g')],
    "securityGroups": [$(echo "\"${SECURITY_GROUPS}\"" | sed 's/,/","/g')],
    "assignPublicIp": "DISABLED"
  }
}
JSON
)

# Create the service if it doesn't exist; otherwise update it.
EXISTING=$(aws ecs describe-services \
  --region "${AWS_REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --services "${SERVICE_NAME}" \
  --query 'services[?status==`ACTIVE`] | length(@)' \
  --output text)

if [ "${EXISTING}" = "0" ]; then
  echo ">> Creating ECS service ${SERVICE_NAME} in cluster ${CLUSTER_NAME}"
  aws ecs create-service \
    --region "${AWS_REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --service-name "${SERVICE_NAME}" \
    --task-definition "${TASK_DEF_ARN}" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "${NETWORK_CONFIG}" \
    --tags "key=preview,value=pr-${PR_NUMBER}" >/dev/null
else
  echo ">> Updating existing ECS service ${SERVICE_NAME}"
  aws ecs update-service \
    --region "${AWS_REGION}" \
    --cluster "${CLUSTER_NAME}" \
    --service "${SERVICE_NAME}" \
    --task-definition "${TASK_DEF_ARN}" \
    --desired-count 1 \
    --force-new-deployment >/dev/null
fi

echo ">> Waiting for service ${SERVICE_NAME} to reach a stable state"
aws ecs wait services-stable \
  --region "${AWS_REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --services "${SERVICE_NAME}"

# The ALB in front of the cluster routes by Host header. A listener rule
# keyed to pr-${PR_NUMBER}.${PREVIEW_DOMAIN} should forward to the service's
# target group (provisioned once per preview by separate infra).
PREVIEW_URL="https://pr-${PR_NUMBER}.${PREVIEW_DOMAIN}"

echo ">> Preview ready: ${PREVIEW_URL}"
echo "preview_url=${PREVIEW_URL}"
