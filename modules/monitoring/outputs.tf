output "monitoring_namespace" {
  description = "Namespace, у якому розгорнуто Prometheus"
  value       = kubernetes_namespace_v1.monitoring.metadata[0].name
}

output "prometheus_release_name" {
  description = "Назва Helm-релізу Prometheus"
  value       = helm_release.prometheus.name
}

output "prometheus_service_url" {
  description = "Внутрішній кластерний URL сервера Prometheus"
  value       = "http://${var.release_name}-server.${var.namespace}.svc.cluster.local"
}

output "port_forward_command" {
  description = "Команда для локального доступу до веб-інтерфейсу Prometheus"
  value       = "kubectl port-forward -n ${var.namespace} svc/${var.release_name}-server 9090:80"
}

output "prometheus_url" {
  description = "Зовнішній HTTPS URL Prometheus (якщо ingress_enabled = true)"
  value       = var.ingress_enabled ? "https://${var.prometheus_host}" : "disabled (use port_forward_command)"
}

output "grafana_url" {
  description = "HTTPS URL веб-інтерфейсу Grafana"
  value       = var.grafana_enabled && var.grafana_ingress_enabled ? "https://${var.grafana_host}" : null
}

output "grafana_admin_password_command" {
  description = "Команда для отримання пароля адміністратора Grafana"
  value       = "kubectl get secret -n ${var.namespace} grafana-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d; echo"
}
