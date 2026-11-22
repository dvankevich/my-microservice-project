output "ingress_elb_hostname" {
  description = "DNS-ім'я AWS LoadBalancer для налаштування CNAME-записів"
  value       = try(data.kubernetes_service_v1.ingress_nginx_controller.status[0].load_balancer[0].ingress[0].hostname, "")
}

output "cluster_issuer_name" {
  description = "Ім'я активного cert-manager ClusterIssuer"
  value       = var.cluster_issuer_name
}
