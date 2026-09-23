# keda-karpenter-gke-demo

A working demo of the "SQS backlog triggers KEDA, which triggers Karpenter,
which scales nodes 0→N→0" pattern — built and run entirely on **GCP**. The
architecture maps directly; only the managed-service names change.

## Architecture

```mermaid
flowchart TB
    LG["load-generator (publish.py)"] -->|"burst N messages"| TOPIC(["Pub/Sub topic<br/>keda-demo-work-queue"])
    TOPIC --> SUB(["Pub/Sub subscription<br/>tracks backlog depth"])

    SUB -->|"polls num_undelivered_messages<br/>every 15s"| KEDA["KEDA operator + ScaledObject<br/>· baseline node pool, 1x e2-small, always on"]

    KEDA -->|"scales Deployment<br/>0 to 10 replicas"| DEPLOY["pubsub-consumer Deployment"]

    DEPLOY -.->|"Pending pods trigger"| AUTOSCALER["GKE cluster autoscaler<br/>· keda-workload pool, 0 to 2x e2-small<br/>· plays the Karpenter role"]
    AUTOSCALER -.->|"provisions / removes nodes for"| DEPLOY

    DEPLOY --> PODS["consumer pods<br/>pull + ack messages"]
    SUB -->|"pull + ack"| PODS

    KEDA --> DASH["Cloud Monitoring dashboard<br/>queue depth, pod count, node count over time"]
    AUTOSCALER --> DASH
```

The `keda-workload` pool is **0 nodes / $0 compute** at rest. A burst of
messages is what temporarily materializes it, and it disappears again once
the queue drains and the cooldown period passes.

## AWS → GCP mapping

| AWS (the scenario this demos) | GCP (what's actually running here) |
|---|---|
| EKS | GKE Standard, zonal cluster |
| SQS | Cloud Pub/Sub (topic + subscription) |
| KEDA on EKS | KEDA on GKE (unchanged — KEDA is Kubernetes-native) |
| Karpenter | GKE cluster autoscaler on a dedicated 0→2 node pool ([terraform/karpenter](terraform/karpenter) has notes on running literal Karpenter-for-GKE instead) |
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
7. Idle-state cost: one `e2-small` baseline node, plus Pub/Sub and Artifact
   Registry (pay-per-use, negligible at this volume). Both node pools use
   `e2-small` rather than the Always Free `e2-micro` type -- in practice
   `e2-micro`'s ~640Mi allocatable memory is consumed almost entirely by
   GKE's own per-node system daemonsets (kube-proxy, CNI, logging/metrics
   agents) before any workload pod is scheduled, so it can't actually run
   anything on GKE Standard, not even KEDA's own control-plane pods.
   `e2-small` is still a few cents/hour. The zonal cluster's management fee
   is waived (one free zonal cluster per billing account), and the
   `keda-workload` pool is $0 while scaled to zero. This is the honest
   floor for "cheap" on GKE Standard, not literally $0.

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
scripts/up.sh          # one-shot end-to-end provision + deploy
scripts/down.sh        # one-shot full teardown
.github/workflows/    # terraform plan/apply CI, and build/push/deploy for the consumer image
```

## Running it yourself

Prerequisites: a GCP project with billing enabled, `gcloud`, `terraform`,
`kubectl`, `docker`.

```bash
# One-time: GCS bucket for terraform state (name must be globally unique)
gsutil mb -l us-central1 gs://<your-project-id>-keda-demo-tfstate

# Edit terraform/backend.tf and terraform/variables.tf defaults to your project ID

PROJECT_ID=<your-project-id> ./scripts/up.sh
```

That provisions everything and deploys the consumer image. Then trigger the
demo and watch it scale:

```bash
pip install -r app/load-generator/requirements.txt
python app/load-generator/publish.py --project <project-id> --topic keda-demo-work-queue --count 200

watch kubectl get pods -n keda-demo
watch kubectl get nodes -l cloud.google.com/gke-nodepool=keda-workload
```

When you're done:

```bash
PROJECT_ID=<your-project-id> ./scripts/down.sh
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

The GitHub Actions service account also needs read/write access to the
Terraform state bucket itself -- this is a bootstrap step outside Terraform
(the bucket has to exist before `terraform init` can use it as a backend,
so it can't grant access to itself):

```bash
gsutil iam ch serviceAccount:$(terraform output -raw github_actions_service_account):roles/storage.objectAdmin \
  gs://<your-project-id>-keda-demo-tfstate
```

## Teardown

`scripts/down.sh` deletes pushed container images (Terraform can't remove a
non-empty Artifact Registry repo) and then runs `terraform destroy` —
removing the cluster, node pools, Pub/Sub, IAM/Workload Identity, Artifact
Registry, and the monitoring dashboard. Brings the project back to $0.

## Screenshots

Captured from a live run against `claude-code-507112` on 2026-09-23: 200
messages published, KEDA scaled the consumer Deployment 0→10, the GKE
cluster autoscaler provisioned 2 nodes on `keda-workload`, the backlog
drained, and everything scaled back to zero.

**Scaled up** — `ScaledObject` active, 10/10 pods `Running` across 2
autoscaler-provisioned nodes:
![Scaled up](docs/screenshots/01-scaled-up.png)

**Scaled back to zero** — backlog drained, pods gone, the `keda-workload`
node draining (`SchedulingDisabled`) on its way out:
![Scaled down](docs/screenshots/02-scaled-down.png)

**Backlog drain, measured via Cloud Monitoring** — `num_undelivered_messages`
on the subscription, sampled every minute:
![Backlog timeline](docs/screenshots/03-backlog-timeline.png)
