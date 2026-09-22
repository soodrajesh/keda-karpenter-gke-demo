# GKE Standard cluster (zonal, to keep idle cost minimal).
# Two node pools:
#   - "baseline": fixed size 1, hosts kube-system + the KEDA operator so the
#     control loop that watches Pub/Sub backlog is always running.
#   - "keda-workload": autoscales 0 -> N. This is the pool that plays the role
#     Karpenter plays on EKS: it is empty (0 nodes, $0 compute) until KEDA
#     scales the consumer Deployment up and pods go Pending, then the GKE
#     cluster autoscaler provisions nodes for them, and removes them again
#     once the pods scale back to zero and the pool drains.
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone
  project  = var.project_id

  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  cluster_autoscaling {
    autoscaling_profile = "OPTIMIZE_UTILIZATION"
  }

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {}

  deletion_protection = false

  depends_on = [google_project_service.required]
}

resource "google_container_node_pool" "baseline" {
  name     = "baseline"
  cluster  = google_container_cluster.primary.name
  location = var.zone
  project  = var.project_id

  node_count = 1

  node_config {
    machine_type    = "e2-small"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

resource "google_container_node_pool" "keda_workload" {
  name     = "keda-workload"
  cluster  = google_container_cluster.primary.name
  location = var.zone
  project  = var.project_id

  autoscaling {
    min_node_count = 0
    max_node_count = 5
  }

  node_config {
    machine_type    = "e2-small"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      workload = "keda-demo"
    }

    taint {
      key    = "keda-demo"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

resource "google_service_account" "gke_nodes" {
  account_id   = "keda-demo-gke-nodes"
  display_name = "GKE nodes SA for keda-karpenter-gke-demo"
  project      = var.project_id
}

resource "google_project_iam_member" "gke_nodes_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metrics" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}
