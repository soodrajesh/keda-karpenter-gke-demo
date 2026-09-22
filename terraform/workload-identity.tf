# --- Pod -> Pub/Sub identity (Workload Identity) ---------------------------
# The consumer pod runs as KSA "pubsub-consumer" in the "keda-demo" namespace.
# That KSA impersonates this GSA, which has pull/publish rights on the topic.
# No JSON keys are created or downloaded anywhere.
resource "google_service_account" "pubsub_consumer" {
  account_id   = "keda-demo-pubsub-consumer"
  display_name = "Workload Identity SA for the keda-demo Pub/Sub consumer"
  project      = var.project_id
}

resource "google_pubsub_subscription_iam_member" "consumer_subscriber" {
  subscription = google_pubsub_subscription.work_queue_sub.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.pubsub_consumer.email}"
  project      = var.project_id
}

resource "google_pubsub_topic_iam_member" "publisher_publisher" {
  topic   = google_pubsub_topic.work_queue.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.pubsub_consumer.email}"
  project = var.project_id
}

resource "google_service_account_iam_member" "consumer_workload_identity_binding" {
  service_account_id = google_service_account.pubsub_consumer.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.consumer_ksa}]"
}

# --- GitHub Actions -> GCP identity (Workload Identity Federation) --------
# CI authenticates via OIDC token exchange, no long-lived service-account
# key is ever stored as a GitHub secret.
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions"
  project                   = var.project_id

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id         = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC"
  project                            = var.project_id

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_actions" {
  account_id   = "keda-demo-github-actions"
  display_name = "GitHub Actions deployer for keda-karpenter-gke-demo"
  project      = var.project_id
}

resource "google_service_account_iam_member" "github_actions_wif_binding" {
  service_account_id = google_service_account.github_actions.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

resource "google_project_iam_member" "github_actions_gke" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_actions_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# The terraform-plan-apply workflow manages GKE, Pub/Sub, and the two
# Workload Identity service accounts above, so it needs these specific
# roles rather than a broad Editor/Owner grant.
resource "google_project_iam_member" "github_actions_gke_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_actions_pubsub_admin" {
  project = var.project_id
  role    = "roles/pubsub.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_actions_sa_admin" {
  project = var.project_id
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_actions_wip_admin" {
  project = var.project_id
  role    = "roles/iam.workloadIdentityPoolAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}
