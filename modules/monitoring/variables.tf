variable "release_name" {
  description = "Назва Helm-релізу Prometheus"
  type        = string
  default     = "prometheus"
}

variable "namespace" {
  description = "Kubernetes namespace для стеку моніторингу"
  type        = string
  default     = "monitoring"
}

variable "chart_version" {
  description = "Версія Helm-чарту prometheus-community/prometheus (null = останній стабільний реліз)"
  type        = string
  default     = null
}

variable "storage_class_name" {
  description = "StorageClass для збереження метрик Prometheus (TSDB)"
  type        = string
  default     = "ebs-gp3"
}

variable "storage_size" {
  description = "Розмір EBS-тому для даних Prometheus"
  type        = string
  default     = "5Gi"
}

variable "retention" {
  description = "Період зберігання метрик у локальній TSDB Prometheus"
  type        = string
  default     = "3d"
}

variable "ingress_enabled" {
  description = "Увімкнути зовнішній HTTPS-доступ до Prometheus через ingress-nginx (рекомендовано false без auth-proxy)"
  type        = bool
  default     = false
}

variable "prometheus_host" {
  description = "Доменне ім'я для Prometheus Ingress (якщо ingress_enabled = true)"
  type        = string
  default     = "prometheus.dvankevich.pp.ua"
}

variable "cluster_issuer_name" {
  description = "Назва cert-manager ClusterIssuer для TLS-сертифіката"
  type        = string
  default     = "letsencrypt-prod"
}

variable "grafana_enabled" {
  description = "Чи розгортати Grafana разом із Prometheus"
  type        = bool
  default     = true
}

variable "grafana_host" {
  description = "Доменне ім'я для веб-інтерфейсу Grafana"
  type        = string
  default     = "grafana.dvankevich.pp.ua"
}

variable "grafana_ingress_enabled" {
  description = "Чи відкривати Grafana назовні через ingress-nginx"
  type        = bool
  default     = true
}
