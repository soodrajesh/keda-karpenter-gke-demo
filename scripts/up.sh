#!/usr/bin/env bash
# End-to-end spin-up: provisions GKE + Pub/Sub + KEDA via Terraform, then
# builds/pushes the consumer image and applies the k8s manifests.
#
# Usage: ./scripts/up.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${PROJECT_ID:-claude-code-507112}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
CLUSTER="${CLUSTER:-keda-karpenter-demo}"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/keda-demo/consumer:$(date +%s)"

echo "==> terraform apply"
cd "$ROOT_DIR/terraform"
terraform init -input=false
terraform apply -auto-approve

echo "==> fetching cluster credentials"
gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID"

echo "==> building and pushing consumer image: $IMAGE_URI"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
docker build -t "$IMAGE_URI" "$ROOT_DIR/app/consumer"
docker push "$IMAGE_URI"

echo "==> deploying k8s manifests"
kubectl apply -f "$ROOT_DIR/k8s/keda-scaledobject-pubsub.yaml"
sed "s#us-central1-docker.pkg.dev/__PROJECT_ID__/keda-demo/consumer:latest#${IMAGE_URI}#; s#__PROJECT_ID__#${PROJECT_ID}#g" \
  "$ROOT_DIR/k8s/consumer-deployment.yaml" | kubectl apply -f -

echo "==> done. Cluster is up, consumer image deployed, KEDA watching the Pub/Sub subscription."
echo "    Trigger the demo with:"
echo "    python app/load-generator/publish.py --project $PROJECT_ID --topic keda-demo-work-queue --count 200"
echo "    Watch with: kubectl get pods -n keda-demo -w"
echo "    Node scale: kubectl get nodes -l cloud.google.com/gke-nodepool=keda-workload -w"
