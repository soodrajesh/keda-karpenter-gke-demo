# KEDA's gcp-pubsub scaler authenticates via GKE Workload Identity on the
# KEDA operator's own pod (TriggerAuthentication with podIdentity: gcp), so
# the operator's KSA needs read access to Pub/Sub + Cloud Monitoring.
resource "google_service_account" "keda_operator" {
  account_id   = "keda-demo-keda-operator"
  display_name = "Workload Identity SA for the KEDA operator"
  project      = var.project_id
}

# keda_operator also needs roles/monitoring.viewer and roles/pubsub.viewer
# -- granted out-of-band, same reason and same bootstrap command as
# workload-identity.tf (see README's CI/CD section).

resource "google_service_account_iam_member" "keda_operator_workload_identity_binding" {
  service_account_id = google_service_account.keda_operator.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[keda/keda-operator]"
}

resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"
  }
  depends_on = [google_container_node_pool.baseline]
}

resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  namespace  = kubernetes_namespace.keda.metadata[0].name
  version    = "2.16.0"

  # The keda-workload pool carries a NoSchedule taint the operator has no
  # toleration for, so it always lands on the untainted baseline pool.
  set {
    name  = "serviceAccount.operator.name"
    value = "keda-operator"
  }

  set {
    name  = "serviceAccount.operator.annotations.iam\\.gke\\.io/gcp-service-account"
    value = google_service_account.keda_operator.email
  }

  # The chart's default 100m/100Mi request per component (300m/300Mi total)
  # doesn't fit next to GKE's own system daemonsets on a small baseline
  # node. These three pods do almost no work at this demo's scale, so
  # trimming requests is safe and keeps the baseline node cheap.
  set {
    name  = "resources.operator.requests.cpu"
    value = "20m"
  }
  set {
    name  = "resources.operator.requests.memory"
    value = "64Mi"
  }
  set {
    name  = "resources.metricServer.requests.cpu"
    value = "20m"
  }
  set {
    name  = "resources.metricServer.requests.memory"
    value = "64Mi"
  }
  # Admission webhooks only validate ScaledObject/TriggerAuthentication CRDs
  # on create/update -- not required for scaling to work, and the baseline
  # node's memory margin is too tight to also fit this third pod.
  set {
    name  = "webhooks.enabled"
    value = "false"
  }

  depends_on = [
    google_container_node_pool.baseline,
    google_service_account_iam_member.keda_operator_workload_identity_binding,
  ]
}

resource "kubernetes_namespace" "keda_demo" {
  metadata {
    name = var.k8s_namespace
  }
  depends_on = [google_container_node_pool.baseline]
}

resource "kubernetes_service_account" "pubsub_consumer" {
  metadata {
    name      = var.consumer_ksa
    namespace = kubernetes_namespace.keda_demo.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.pubsub_consumer.email
    }
  }
}
