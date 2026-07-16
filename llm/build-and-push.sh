#!/usr/bin/env bash
set -euo pipefail

# ---- Config -----------------------------------------------------------------
AWS_REGION="${AWS_REGION:-us-east-1}"
# Must match the Terraform-managed repo name: "${project_name}-ecr".
# The ECR repo is created by Terraform (modules/compute), NOT by this script.
REPO="${REPO:-aws-llm-ecr}"
# ECR tags are IMMUTABLE (set in Terraform), so a static tag like "v1" can only
# be pushed once. Default to "sha-<short git SHA>" (falls back to a timestamp)
# so every build gets a unique, re-pushable tag. The "sha-" prefix matches the
# ECR lifecycle rule that garbage-collects CI images (Terraform: modules/compute).
TAG="${TAG:-sha-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d-%H%M%S)}"
# -----------------------------------------------------------------------------

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# The repo is owned by Terraform. Verify it exists — do NOT create it here, or
# you'd create an unmanaged repo that drifts from state and lacks the hardening
# (immutable tags, scan-on-push) Terraform applies.
aws ecr describe-repositories --repository-names "$REPO" --region "$AWS_REGION" >/dev/null 2>&1 \
  || { echo "ERROR: ECR repo '$REPO' not found in $AWS_REGION. Run 'terraform apply' first."; exit 1; }

# Build for amd64 — EKS nodes are amd64 (AL2023_x86_64_*), and an arm64 image
# (e.g. from an Apple Silicon Mac) will fail to run on them with exec format error.
docker build --platform linux/amd64 -t "${REPO}:${TAG}" .

# Authenticate Docker to ECR.
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_URI"

# Tag and push.
docker tag "${REPO}:${TAG}" "${ECR_URI}/${REPO}:${TAG}"
docker push "${ECR_URI}/${REPO}:${TAG}"

echo ""
echo "Pushed: ${ECR_URI}/${REPO}:${TAG}"
echo "Set this as the image in your Kubernetes Deployment."
