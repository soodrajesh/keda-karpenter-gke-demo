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
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.consumer_ksa}]"
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
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
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
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# github-actions also needs roles/container.developer (kubectl access) and
# roles/artifactregistry.writer (image push) for build-push-deploy.yml, for
# the same self-management reason below -- granted out-of-band.

# The terraform-plan-apply workflow needs roles/container.admin,
# roles/pubsub.admin, roles/iam.serviceAccountAdmin,
# roles/iam.workloadIdentityPoolAdmin, roles/monitoring.editor (to manage
# the dashboard resource), and roles/compute.viewer (to read the GKE node
# pools' underlying instance groups during refresh) to manage this
# config. These are deliberately NOT declared as Terraform resources here:
# Terraform's provider needs to read/write the *whole* project IAM policy
# to manage a google_project_iam_member binding, which requires
# resourcemanager permissions broader than any of these roles grant on
# their own -- so the github-actions SA can't self-manage its own
# project-level bindings via its own `terraform apply`. Granting it
# something broad enough to do that (roles/resourcemanager.projectIamAdmin
# or wider) defeats the point of scoping it down in the first place. All
# of these roles are granted once, out-of-band, by a human with
# project-level IAM rights -- see README's CI/CD section for the exact
# commands.
