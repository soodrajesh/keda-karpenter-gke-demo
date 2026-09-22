# keda-karpenter-gke-demo

A working demo of the "SQS backlog triggers KEDA, which triggers Karpenter,
which scales nodes 0→N→0" pattern — built and run entirely on **GCP**
because that's what I had access to, not AWS. The architecture maps
directly; only the managed-service names change.

## AWS → GCP mapping

| AWS (the scenario this demos) | GCP (what's actually running here) |
|---|---|
| EKS | GKE Standard, zonal cluster |
| SQS | Cloud Pub/Sub (topic + subscription) |
| KEDA on EKS | KEDA on GKE (unchanged — KEDA is Kubernetes-native) |
| Karpenter | GKE cluster autoscaler on a dedicated 0→5 node pool ([terraform/karpenter](terraform/karpenter) has notes on running literal Karpenter-for-GKE instead) |
| IRSA | GKE Workload Identity |
| CloudWatch | Cloud Monitoring |

## How the demo works

1. `app/load-generator/publish.py` bursts ~200 messages into the Pub/Sub
   topic (`keda-demo-work-queue`), simulating a spike in incoming SQS
   traffic.
2. KEDA's `gcp-pubsub` scaler (`k8s/keda-scaledobject-pubsub.yaml`) polls the
   subscription's undelivered-message count every 15s and scales the
   `pubsub-consumer` Deployment from 0 up to 10 replicas (1 pod per 10
   backlogged messages).
3. Those pods are unschedulable on the empty `keda-workload` node pool, so
   GKE's cluster autoscaler provisions nodes for them — this is the role
   Karpenter plays on EKS.
4. The consumer pods drain the queue (each message takes ~5s to simulate
   work) and ack each message.
5. Once the subscription is empty for `cooldownPeriod` (60s), KEDA scales
   the Deployment back to 0 replicas.
6. With no pods left requesting resources, the cluster autoscaler removes
   the now-empty nodes from `keda-workload` back down to 0.
7. Idle-state cost: one `e2-small` baseline node + Pub/Sub + GKE control
   plane management fee. Everything else is $0 when there's no traffic.

Watch it happen on the Cloud Monitoring dashboard Terraform creates
(`terraform output monitoring_dashboard_url`): queue backlog, node count,
and pod count all rise together and fall back to zero together.

## Repo layout

```
terraform/           # GKE cluster, node pools, Pub/Sub, Workload Identity, KEDA helm release, dashboard
terraform/karpenter/  # notes on running literal Karpenter-for-GKE instead of the native autoscaler
k8s/                  # consumer Deployment + KEDA TriggerAuthentication/ScaledObject
app/consumer/         # Python service that pulls from Pub/Sub and simulates work
app/load-generator/   # script that bursts messages in to trigger a scale-up
.github/workflows/    # terraform plan/apply CI, and build/push/deploy for the consumer image
```

## Running it yourself

Prerequisites: a GCP project with billing enabled, `gcloud`, `terraform`,
`kubectl`, `docker`.

```bash
# One-time: GCS bucket for terraform state (name must be globally unique)
gsutil mb -l us-central1 gs://<your-project-id>-keda-demo-tfstate

# Edit terraform/backend.tf and terraform/variables.tf defaults to your project ID

cd terraform
terraform init
terraform apply

# Get cluster creds
$(terraform output -raw get_credentials_command)

# Build and push the consumer image (or let the GitHub Actions workflow do it)
gcloud auth configure-docker us-central1-docker.pkg.dev
docker build -t us-central1-docker.pkg.dev/<project-id>/keda-demo/consumer:latest app/consumer
docker push us-central1-docker.pkg.dev/<project-id>/keda-demo/consumer:latest

kubectl apply -f k8s/keda-scaledobject-pubsub.yaml
kubectl apply -f k8s/consumer-deployment.yaml   # after substituting PROJECT_ID in the image ref

# Trigger the demo
pip install -r app/load-generator/requirements.txt
python app/load-generator/publish.py --project <project-id> --topic keda-demo-work-queue --count 200

# Watch it scale
watch kubectl get pods -n keda-demo
watch kubectl get nodes -l cloud.google.com/gke-nodepool=keda-workload
```

## CI/CD

- **`terraform-plan-apply.yml`** — `terraform plan` on PRs touching
  `terraform/**`, `terraform apply` on merge to `main`. Authenticates via
  Workload Identity Federation (OIDC) — no service-account JSON key is ever
  stored as a GitHub secret.
- **`build-push-deploy.yml`** — builds the consumer image, pushes to
  Artifact Registry, applies the k8s manifests.

Both workflows need two repo variables set (`Settings → Secrets and
variables → Actions → Variables`), which come from Terraform's own output:

```bash
terraform output workload_identity_provider   # -> WIF_PROVIDER
terraform output github_actions_service_account  # -> WIF_SERVICE_ACCOUNT
```

## Teardown

```bash
cd terraform
terraform destroy
```

Everything here is designed to cost effectively $0 when idle (node pools
scale to 0, Pub/Sub and Artifact Registry are pay-per-use), but `destroy`
removes it entirely when you're done.
