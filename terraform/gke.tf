# GKE Standard cluster (zonal, in us-central1 -- one of the Always Free
# regions -- to stay inside GCP's free tier as much as this workload allows):
#   - Zonal Standard clusters get the $0.10/hr cluster management fee waived
#     (one free zonal cluster per billing account).
#   - Both node pools use e2-micro, the Always Free machine type, with a
#     30GB pd-standard boot disk (the Always Free persistent-disk allowance).
# Two node pools:
#   - "baseline": fixed size 1, hosts kube-system + the KEDA operator so the
#     control loop that watches Pub/Sub backlog is always running. This one
#     node is exactly what Always Free's "1 e2-micro/month" allowance covers.
#   - "keda-workload": autoscales 0 -> N. This is the pool that plays the role
#     Karpenter plays on EKS: it is empty (0 nodes, $0 compute) until KEDA
#     scales the consumer Deployment up and pods go Pending, then the GKE
#     cluster autoscaler provisions nodes for them, and removes them again
#     once the pods scale back to zero and the pool drains. Nodes here are
#     billed (at e2-micro's small hourly rate) only while a burst is active,
#     since they're on top of the one free-tier instance already used by
#     "baseline".
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
    # e2-micro (Always Free) has only ~640Mi allocatable after GKE's
    # per-node system daemonsets -- not enough room for the KEDA operator +
    # admission-webhook + metrics-apiserver together. e2-small is a few
    # cents/hour and this demo is torn down right after, so it's the
    # pragmatic choice for the one node that must always schedule KEDA.
    machine_type    = "e2-small"
    disk_type       = "pd-standard"
    disk_size_gb    = 30
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
    max_node_count = 2
  }

  node_config {
    machine_type    = "e2-micro"
    disk_type       = "pd-standard"
    disk_size_gb    = 30
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
