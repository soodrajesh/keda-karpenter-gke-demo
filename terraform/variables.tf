variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "claude-code-507112"
}

variable "region" {
  description = "GCP region for the cluster and regional resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Single zone used for the zonal GKE cluster (keeps idle cost near zero)"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "keda-karpenter-demo"
}

variable "pubsub_topic" {
  description = "Pub/Sub topic name that stands in for the SQS queue"
  type        = string
  default     = "keda-demo-work-queue"
}

variable "pubsub_subscription" {
  description = "Pub/Sub subscription the consumer pulls from and KEDA watches for backlog"
  type        = string
  default     = "keda-demo-work-queue-sub"
}

variable "k8s_namespace" {
  description = "Namespace for the consumer workload"
  type        = string
  default     = "keda-demo"
}

variable "consumer_ksa" {
  description = "Kubernetes service account used by the consumer pods (bound via Workload Identity)"
  type        = string
  default     = "pubsub-consumer"
}

variable "github_repo" {
  description = "GitHub repo in owner/name form, used to scope the Workload Identity Federation pool for GitHub Actions"
  type        = string
  default     = "soodrajesh/keda-karpenter-gke-demo"
}
