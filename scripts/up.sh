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

echo "==> granting bootstrap IAM roles (idempotent -- safe to re-run)"
echo "    These can't be Terraform resources (see README's CI/CD section for"
echo "    why), and importantly aren't a true one-time step: destroying and"
echo "    recreating these service accounts (e.g. via scripts/down.sh then"
echo "    this script) invalidates every prior grant, since IAM bindings"
echo "    resolve to the account's underlying unique ID, not just its email."
SA="serviceAccount:keda-demo-github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
for role in roles/container.admin roles/pubsub.admin roles/iam.serviceAccountAdmin \
            roles/iam.workloadIdentityPoolAdmin roles/container.developer \
            roles/artifactregistry.writer roles/monitoring.editor roles/compute.viewer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="$SA" --role="$role" --condition=None >/dev/null
done
SA="serviceAccount:keda-demo-gke-nodes@${PROJECT_ID}.iam.gserviceaccount.com"
for role in roles/logging.logWriter roles/monitoring.metricWriter roles/artifactregistry.reader; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="$SA" --role="$role" --condition=None >/dev/null
done
SA="serviceAccount:keda-demo-keda-operator@${PROJECT_ID}.iam.gserviceaccount.com"
for role in roles/monitoring.viewer roles/pubsub.viewer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="$SA" --role="$role" --condition=None >/dev/null
done
# GCS bucket IAM has the same staleness issue and isn't a project-level
# binding, so it needs its own grant too.
gsutil iam ch "serviceAccount:keda-demo-github-actions@${PROJECT_ID}.iam.gserviceaccount.com:roles/storage.objectAdmin" \
  "gs://${PROJECT_ID}-keda-demo-tfstate" >/dev/null 2>&1 || true

echo "==> ensuring gke-gcloud-auth-plugin is installed (required by kubectl)"
gcloud components install gke-gcloud-auth-plugin --quiet
export USE_GKE_GCLOUD_AUTH_PLUGIN=True

echo "==> fetching cluster credentials"
gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT_ID"

echo "==> building and pushing consumer image: $IMAGE_URI"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
# GKE nodes are amd64 regardless of the machine this script runs on (e.g. Apple
# Silicon defaults to arm64 and produces an image the nodes can't pull).
docker build --platform linux/amd64 -t "$IMAGE_URI" "$ROOT_DIR/app/consumer"
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
