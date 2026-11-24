# 1. Окремий namespace для моніторингу
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# 2. Основний Helm-реліз Prometheus (server + node-exporter + kube-state-metrics)
resource "helm_release" "prometheus" {
  name             = var.release_name
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = var.chart_version
  create_namespace = false
  timeout          = 600

  values = [
    templatefile("${path.module}/values.yaml", {
      retention           = var.retention
      storage_class_name  = var.storage_class_name
      storage_size        = var.storage_size
      ingress_enabled     = var.ingress_enabled
      prometheus_host     = var.prometheus_host
      cluster_issuer_name = var.cluster_issuer_name
    })
  ]
}

# 3. Локальний Helm-чарт для кастомних правил/ресурсів моніторингу
resource "helm_release" "monitoring_extras" {
  name             = "${var.release_name}-extras"
  chart            = "${path.module}/charts"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false

  values = [
    file("${path.module}/charts/values.yaml")
  ]

  depends_on = [helm_release.prometheus]
}
