# Self-Hosted Preview Environments with GitHub Actions + Docker

Companion code for the Autonoma blog post 'Self-Hosted Preview Environments with GitHub Actions + Docker'. Production-ready GitHub Actions workflows and shell scripts for self-hosted preview environments on any cloud.

> Companion code for the Autonoma blog post: **[Self-Hosted Preview Environments with GitHub Actions + Docker](https://getautonoma.com/blog/self-hosted-preview-environments)**

## Requirements

A GitHub repo, a Dockerfile-buildable app (Next.js used as the reference), an account on one of AWS / GCP / DigitalOcean / Hetzner / Fly.io, and optionally an Autonoma account for the one-API-call testing path.

## Quickstart

```bash
git clone https://github.com/Autonoma-Tools/self-hosted-preview-environments.git
cd self-hosted-preview-environments
# Clone the repo. Copy the .github/workflows/preview.yml into your own repo's
# .github/workflows/ directory. Copy the Dockerfile and .dockerignore to your
# project root. Pick a deploy script for your cloud of choice from scripts/
# and customize the cluster/app names. Set the required secrets
# (AUTONOMA_API_KEY, cloud provider credentials via OIDC) in your GitHub repo
# settings. Open a PR and watch the preview deploy.
```

## Project structure

```
.
├── .dockerignore
├── .github/
│   └── workflows/
│       ├── preview.yml
│       ├── preview-test-autonoma.yml
│       └── preview-test-playwright.yml
├── Dockerfile
├── LICENSE
├── README.md
└── scripts/
    ├── deploy-aws.sh
    ├── deploy-fly.sh
    ├── deploy-gcp.sh
    └── teardown.sh
```

- `Dockerfile` + `.dockerignore` — multi-stage Next.js build using the standalone output mode.
- `.github/workflows/preview.yml` — end-to-end PR pipeline: build, deploy, test, teardown.
- `.github/workflows/preview-test-autonoma.yml` — reusable workflow that runs an Autonoma test folder against the preview URL.
- `.github/workflows/preview-test-playwright.yml` — reusable workflow that runs Playwright E2E tests against the preview URL (alternative to the Autonoma path).
- `scripts/deploy-aws.sh` — deploy the preview image to AWS ECS Fargate.
- `scripts/deploy-gcp.sh` — deploy the preview image to Google Cloud Run.
- `scripts/deploy-fly.sh` — deploy the preview image to Fly.io.
- `scripts/teardown.sh` — idempotent teardown across all five supported providers.

## About

This repository is maintained by [Autonoma](https://getautonoma.com) as reference material for the linked blog post. Autonoma builds autonomous AI agents that plan, execute, and maintain end-to-end tests directly from your codebase.

If something here is wrong, out of date, or unclear, please [open an issue](https://github.com/Autonoma-Tools/self-hosted-preview-environments/issues/new).

## License

Released under the [MIT License](./LICENSE) © 2026 Autonoma Labs.
