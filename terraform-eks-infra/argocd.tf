################################################################################
# ArgoCD
################################################################################

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.9.1" # Argo CD v3.5.3

  create_namespace = true

  values = [
    yamlencode({
      # Schedule ArgoCD's components on the existing "critical-components" managed
      # node group instead of provisioning a dedicated Karpenter node for it - it's
      # cluster infrastructure (like KEDA/ESO), not an app workload.
      global = {
        tolerations = [
          {
            key      = "CriticalAddonsOnly"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]
      }
      server = {
        # Keep it ClusterIP (no LoadBalancer) - no ELB cost, access via
        # `kubectl port-forward svc/argocd-server -n argocd 8080:443`
        service = {
          type = "ClusterIP"
        }
      }
      configs = {
        cm = {
          # App-of-Apps: without this health check ArgoCD does not know when a child
          # Application is Healthy, so sync waves on child Applications would not wait.
          # Custom health check, written in Lua (the scripting language ArgoCD uses for this).
          # It does not probe anything itself: ArgoCD already computes each child Application's
          # health and stores it in `status.health.status`. This script only copies that value
          # (child -> script -> root), because ArgoCD has no built-in rule for how a parent reads
          # the health of an `Application` resource. Without it the root app would not wait for
          # a child to become Healthy, so the sync waves in argocd/apps/*.yaml would not wait.
          # `obj` is the child Application; `~= nil` means "the field exists".
          "resource.customizations.health.argoproj.io_Application" = <<-EOT
            hs = {}
            hs.status = "Progressing"
            hs.message = ""
            if obj.status ~= nil and obj.status.health ~= nil then
              hs.status = obj.status.health.status
              if obj.status.health.message ~= nil then
                hs.message = obj.status.health.message
              end
            end
            return hs
          EOT
        }
      }
    })
  ]

  depends_on = [module.eks]
}
