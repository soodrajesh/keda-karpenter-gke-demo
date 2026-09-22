resource "google_artifact_registry_repository" "consumer" {
  project       = var.project_id
  location      = var.region
  repository_id = "keda-demo"
  format        = "DOCKER"
  description   = "Consumer image for the keda-karpenter-gke-demo"

  depends_on = [google_project_service.required]
}
