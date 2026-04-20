#!/usr/bin/env bash
#
# deploy-fly.sh — Deploy a preview environment to Fly.io.
#
# Required env vars:
#   PR_NUMBER    Pull request number (e.g. 1234)
#   IMAGE        Fully qualified image reference, e.g.
#                ghcr.io/my-org/app:pr-1234
#   FLY_ORG      Fly.io org slug (default: personal)
#   FLY_REGION   Primary region (default: iad)
#
# Requires the FLY_API_TOKEN env var (or a prior `flyctl auth login`).
#
# Outputs (stdout):
#   preview_url=https://preview-pr-<PR_NUMBER>.fly.dev

set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER is required}"
: "${IMAGE:?IMAGE is required}"

FLY_ORG="${FLY_ORG:-personal}"
FLY_REGION="${FLY_REGION:-iad}"
APP_NAME="preview-pr-${PR_NUMBER}"

echo ">> Ensuring Fly app ${APP_NAME} exists (org=${FLY_ORG})"
if ! flyctl apps list --json | grep -q "\"Name\": *\"${APP_NAME}\""; then
  flyctl apps create "${APP_NAME}" --org "${FLY_ORG}"
else
  echo ">> App ${APP_NAME} already exists, reusing it"
fi

echo ">> Deploying image ${IMAGE} to ${APP_NAME}"
# --ha=false keeps one machine per region (plenty for a preview).
# --now skips the interactive confirmation on first deploy.
flyctl deploy \
  --app "${APP_NAME}" \
  --image "${IMAGE}" \
  --primary-region "${FLY_REGION}" \
  --ha=false \
  --now \
  --strategy immediate \
  --wait-timeout 300

PREVIEW_URL="https://${APP_NAME}.fly.dev"

echo ">> Preview ready: ${PREVIEW_URL}"
echo "preview_url=${PREVIEW_URL}"
