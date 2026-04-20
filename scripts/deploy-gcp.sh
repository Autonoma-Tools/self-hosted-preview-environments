#!/usr/bin/env bash
#
# deploy-gcp.sh — Deploy a preview environment to Google Cloud Run.
#
# Required env vars:
#   PR_NUMBER   Pull request number (e.g. 1234)
#   IMAGE       Fully qualified image, e.g.
#               us-central1-docker.pkg.dev/my-project/app/app:pr-1234
#   REGION      Cloud Run region (default: us-central1)
#   PROJECT_ID  GCP project id (optional; falls back to gcloud's default)
#
# Outputs (stdout):
#   preview_url=<https url assigned by Cloud Run>
#
# Idempotent: `gcloud run deploy` creates the service on first run and updates
# it on subsequent runs, so the same script works for `opened` and
# `synchronize` PR events.

set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER is required}"
: "${IMAGE:?IMAGE is required}"

REGION="${REGION:-us-central1}"
SERVICE="preview-pr-${PR_NUMBER}"

PROJECT_FLAG=()
if [ -n "${PROJECT_ID:-}" ]; then
  PROJECT_FLAG=(--project "${PROJECT_ID}")
fi

echo ">> Deploying ${SERVICE} to Cloud Run (${REGION})"
gcloud run deploy "${SERVICE}" \
  "${PROJECT_FLAG[@]}" \
  --image "${IMAGE}" \
  --region "${REGION}" \
  --platform managed \
  --allow-unauthenticated \
  --memory 512Mi \
  --cpu 1 \
  --port 3000 \
  --max-instances 2 \
  --set-env-vars "NODE_ENV=production,PR_NUMBER=${PR_NUMBER}" \
  --labels "preview=true,pr=${PR_NUMBER}" \
  --quiet

PREVIEW_URL=$(gcloud run services describe "${SERVICE}" \
  "${PROJECT_FLAG[@]}" \
  --region "${REGION}" \
  --format 'value(status.url)')

if [ -z "${PREVIEW_URL}" ]; then
  echo "ERROR: Cloud Run did not return a service URL for ${SERVICE}" >&2
  exit 1
fi

echo ">> Preview ready: ${PREVIEW_URL}"
echo "preview_url=${PREVIEW_URL}"
