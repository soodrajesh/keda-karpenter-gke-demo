# Karpenter for GKE (optional / stretch)

The primary demo (`../gke.tf`) uses GKE's native cluster autoscaler with a
dedicated `keda-workload` node pool scaling 0→5. That's the direct,
production-supported equivalent of what Karpenter does on EKS: watch for
unschedulable pods, provision right-sized nodes, remove them when idle.

This directory is **not wired into the root module** and is not applied by
`terraform-plan-apply.yml`. It's a documented path for running the literal
Karpenter binary (`cloud-provider-gcp` / [Karpenter provider for GCP]) on top
of the same cluster, for anyone who wants the closer-to-AWS story.

Why it's kept separate:

- The GCP provider for Karpenter is community-maintained and materially less
  mature than the AWS provider — expect CRD/webhook version drift and rough
  edges that aren't representative of a "day 1 production" setup.
- It needs its own controller service account, its own NodePool/NodeClass
  CRDs, and (unlike the AWS provider) no equivalent of EC2 Fleet — GCP MIGs
  are used instead, which changes the provisioning latency characteristics.

To try it:

1. `helm install karpenter oci://ghcr.io/cloudpilot-ai/charts/karpenter` (or
   the current upstream chart — check the project's releases, the OCI path
   moves).
2. Apply a `NodePool` + `GCENodeClass` targeting the same `keda-demo`
   namespace/taint used in `../k8s/keda-scaledobject-pubsub.yaml`.
3. Remove the `keda_workload` node pool's autoscaling block in `../gke.tf`
   (or just leave both running side by side — they don't conflict, KEDA only
   cares about pod counts, not which controller provisioned the node).

This is intentionally left as a manual, documented exercise rather than
Terraform code, since the provider's API surface is still moving.
