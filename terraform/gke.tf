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
    # e2-micro doesn't leave enough allocatable memory for KEDA's control
    # plane pods once GKE's own system daemonsets land (see keda-workload
    # below for the same finding). e2-small was still too tight in
    # practice: konnectivity-agent autoscales with cluster size (it added
    # a 3rd replica once keda-workload nodes joined), and that alone
    # squeezed the KEDA operator out on reschedule. e2-medium's extra
    # memory gives real headroom; still a few cents/hour for a demo
    # that's torn down right after.
    machine_type    = "e2-medium"
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
    # e2-micro turns out not to work at all here either: GKE's own per-node
    # system daemonsets (kube-proxy, CNI, logging/metrics agents) consume
    # nearly all of its ~640Mi allocatable memory before any workload pod
    # is scheduled, so even a single 64Mi consumer pod can't fit. e2-small
    # is the smallest machine type that actually leaves room for pods.
    machine_type    = "e2-small"
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

# gke_nodes also needs roles/logging.logWriter, roles/monitoring.metricWriter,
# and roles/artifactregistry.reader -- granted out-of-band, same reason and
# same bootstrap command as workload-identity.tf (see README's CI/CD section).
