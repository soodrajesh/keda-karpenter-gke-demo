output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_location" {
  value = google_container_cluster.primary.location
}

output "get_credentials_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${var.zone} --project ${var.project_id}"
}

output "pubsub_topic" {
  value = google_pubsub_topic.work_queue.name
}

output "pubsub_subscription" {
  value = google_pubsub_subscription.work_queue_sub.name
}

output "github_actions_service_account" {
  value = google_service_account.github_actions.email
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "monitoring_dashboard_url" {
  value = "https://console.cloud.google.com/monitoring/dashboards/builder/${element(split("/", google_monitoring_dashboard.keda_demo.id), 1)}?project=${var.project_id}"
}
