# Pub/Sub stands in for SQS: the load-generator publishes messages here,
# the consumer Deployment pulls from the subscription, and KEDA's
# gcp-pubsub scaler watches the subscription's undelivered-message count
# to decide how many consumer pods should exist.
resource "google_pubsub_topic" "work_queue" {
  name    = var.pubsub_topic
  project = var.project_id

  depends_on = [google_project_service.required]
}

resource "google_pubsub_subscription" "work_queue_sub" {
  name    = var.pubsub_subscription
  topic   = google_pubsub_topic.work_queue.name
  project = var.project_id

  ack_deadline_seconds       = 30
  message_retention_duration = "600s"

  expiration_policy {
    ttl = "" # never expires
  }
}
