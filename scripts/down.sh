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
ZONE="${ZONE:-us-central1-a}"
CLUSTER="${CLUSTER:-keda-karpenter-demo}"

echo "==> deleting kubectl-applied resources (ScaledObject, Deployment) while the"
echo "    KEDA operator is still running to process their finalizers -- Terraform"
echo "    has no knowledge of these (they were applied with kubectl, not"
echo "    terraform), so if left for the KEDA operator to disappear mid-destroy,"
echo "    the ScaledObject's finalizer never gets processed and the keda-demo"
echo "    namespace hangs in Terminating forever, blocking terraform destroy"
gcloud components install gke-gcloud-auth-plugin --quiet
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
if gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID"
  kubectl delete -f "$ROOT_DIR/k8s/consumer-deployment.yaml" --ignore-not-found --timeout=60s || true
  kubectl delete -f "$ROOT_DIR/k8s/keda-scaledobject-pubsub.yaml" --ignore-not-found --timeout=60s || true
fi

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
