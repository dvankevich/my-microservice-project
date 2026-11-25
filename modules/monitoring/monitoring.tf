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

# Grafana
resource "random_password" "grafana_admin" {
  count   = var.grafana_enabled ? 1 : 0
  length  = 20
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  count = var.grafana_enabled ? 1 : 0

  metadata {
    name      = "grafana-admin-secret"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin[0].result
  }
}

resource "helm_release" "grafana" {
  count = var.grafana_enabled ? 1 : 0

  name             = "grafana"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  create_namespace = false
  timeout          = 600

  values = [
    templatefile("${path.module}/grafana-values.yaml", {
      storage_class   = var.storage_class_name
      ingress_enabled = var.grafana_ingress_enabled
      grafana_host    = var.grafana_host
      namespace       = var.namespace
    })
  ]

  depends_on = [
    helm_release.prometheus,
    kubernetes_secret_v1.grafana_admin
  ]
}
