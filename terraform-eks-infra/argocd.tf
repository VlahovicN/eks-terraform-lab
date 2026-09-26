################################################################################
# ArgoCD
################################################################################

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.9.1"   # Argo CD v3.5.3

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
    })
  ]

  depends_on = [module.eks]
}
