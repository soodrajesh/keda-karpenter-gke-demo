#!/usr/bin/env bash
# Full teardown: deletes pushed container images (Terraform can't remove a
# non-empty Artifact Registry repo) then destroys every Terraform-managed
# resource -- GKE cluster, node pools, Pub/Sub, IAM/Workload Identity,
# Artifact Registry, monitoring dashboard. Brings the project back to
# exactly $0 for this demo.
#
# Usage: ./scripts/down.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${PROJECT_ID:-claude-code-507112}"
REGION="${REGION:-us-central1}"

echo "==> deleting pushed images from Artifact Registry (if any)"
DIGESTS=$(gcloud artifacts docker images list "${REGION}-docker.pkg.dev/${PROJECT_ID}/keda-demo/consumer" \
  --format="value(version)" 2>/dev/null || true)
for d in $DIGESTS; do
  gcloud artifacts docker images delete \
    "${REGION}-docker.pkg.dev/${PROJECT_ID}/keda-demo/consumer@${d}" --quiet || true
done

echo "==> terraform destroy"
cd "$ROOT_DIR/terraform"
terraform init -input=false
terraform destroy -auto-approve

echo "==> done. All demo resources removed."
