#!/usr/bin/env bash
#
# teardown.sh — Destroy the preview environment for a given pull request on
# any of the five supported providers.
#
# Required env vars:
#   PR_NUMBER   Pull request number (e.g. 1234)
#   PROVIDER    One of: aws | gcp | fly | digitalocean | hetzner | all
#               Defaults to "all" which attempts each provider in sequence.
#
# Optional env vars:
#   CLUSTER_NAME   (aws) ECS cluster name (default: previews)
#   AWS_REGION     (aws) default: us-east-1
#   REGION         (gcp) Cloud Run region (default: us-central1)
#   PROJECT_ID     (gcp) optional project override
#
# Idempotency pattern
# -------------------
# Every provider call ends in `|| true`. This is deliberate: the script is
# called from the `closed` PR event, and a PR may be closed without ever
# having deployed (draft, CI failed, first push closed), so the resources we
# target may not exist. Treating "already deleted" as success keeps the job
# green and keeps teardown cheap to call repeatedly.

set -uo pipefail

: "${PR_NUMBER:?PR_NUMBER is required}"
PROVIDER="${PROVIDER:-all}"

APP_NAME="preview-pr-${PR_NUMBER}"

teardown_aws() {
  local cluster="${CLUSTER_NAME:-previews}"
  local region="${AWS_REGION:-us-east-1}"
  echo ">> [aws] Scaling ${APP_NAME} to 0 on cluster ${cluster}"
  aws ecs update-service \
    --region "${region}" \
    --cluster "${cluster}" \
    --service "${APP_NAME}" \
    --desired-count 0 >/dev/null 2>&1 || true

  echo ">> [aws] Deleting service ${APP_NAME}"
  aws ecs delete-service \
    --region "${region}" \
    --cluster "${cluster}" \
    --service "${APP_NAME}" \
    --force >/dev/null 2>&1 || true

  echo ">> [aws] Deregistering task definitions for family ${APP_NAME}"
  local arns
  arns=$(aws ecs list-task-definitions \
    --region "${region}" \
    --family-prefix "${APP_NAME}" \
    --query 'taskDefinitionArns' \
    --output text 2>/dev/null || true)
  for arn in ${arns}; do
    aws ecs deregister-task-definition \
      --region "${region}" \
      --task-definition "${arn}" >/dev/null 2>&1 || true
  done
}

teardown_gcp() {
  local region="${REGION:-us-central1}"
  local project_flag=()
  if [ -n "${PROJECT_ID:-}" ]; then
    project_flag=(--project "${PROJECT_ID}")
  fi
  echo ">> [gcp] Deleting Cloud Run service ${APP_NAME}"
  gcloud run services delete "${APP_NAME}" \
    "${project_flag[@]}" \
    --region "${region}" \
    --quiet 2>/dev/null || true
}

teardown_fly() {
  echo ">> [fly] Destroying Fly app ${APP_NAME}"
  flyctl apps destroy "${APP_NAME}" -y 2>/dev/null || true
}

teardown_digitalocean() {
  echo ">> [digitalocean] Looking up app id for ${APP_NAME}"
  local app_id
  app_id=$(doctl apps list --format ID,Spec.Name --no-header 2>/dev/null \
    | awk -v name="${APP_NAME}" '$2 == name {print $1}' \
    | head -n1 || true)
  if [ -n "${app_id}" ]; then
    echo ">> [digitalocean] Deleting app ${app_id}"
    doctl apps delete "${app_id}" --force 2>/dev/null || true
  else
    echo ">> [digitalocean] No app found for ${APP_NAME}, skipping"
  fi
}

teardown_hetzner() {
  echo ">> [hetzner] Deleting servers tagged pr=${PR_NUMBER}"
  # hcloud lists label selectors as `server list -l key=value`.
  local server_ids
  server_ids=$(hcloud server list \
    -l "preview=true,pr=${PR_NUMBER}" \
    -o columns=id -o noheader 2>/dev/null || true)
  for id in ${server_ids}; do
    hcloud server delete "${id}" 2>/dev/null || true
  done
}

case "${PROVIDER}" in
  aws)           teardown_aws ;;
  gcp)           teardown_gcp ;;
  fly)           teardown_fly ;;
  digitalocean)  teardown_digitalocean ;;
  hetzner)       teardown_hetzner ;;
  all)
    teardown_aws
    teardown_gcp
    teardown_fly
    teardown_digitalocean
    teardown_hetzner
    ;;
  *)
    echo "ERROR: unknown PROVIDER '${PROVIDER}'" >&2
    echo "Valid values: aws | gcp | fly | digitalocean | hetzner | all" >&2
    exit 2
    ;;
esac

echo ">> Teardown for PR ${PR_NUMBER} (${PROVIDER}) complete"
