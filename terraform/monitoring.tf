# A single dashboard to watch the whole scale-out/scale-in story: queue
# backlog going up, pod count following it, node count following that,
# and everything coming back down to zero.
resource "google_monitoring_dashboard" "keda_demo" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "KEDA + GKE autoscale-to-zero demo"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "Pub/Sub undelivered messages (the SQS-style backlog)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${var.pubsub_subscription}\" AND metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "GKE node count by pool"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"k8s_node\" AND resource.labels.cluster_name=\"${var.cluster_name}\" AND metric.type=\"kubernetes.io/node/status/condition\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_COUNT_TRUE"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Consumer pod count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"k8s_pod\" AND resource.labels.namespace_name=\"${var.k8s_namespace}\" AND metric.type=\"kubernetes.io/pod/network/received_bytes_count\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_COUNT"
                  }
                }
              }
            }]
          }
        }
      ]
    }
  })
}
