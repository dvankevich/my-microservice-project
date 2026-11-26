variable "ingress_replica_count" {
  description = "Кількість реплік ingress-nginx-controller для Multi-AZ HA"
  type        = number
  default     = 2
}

variable "acme_email" {
  description = "Email для сповіщень Let's Encrypt про сертифікати"
  type        = string
  default     = "admin@dvankevich.pp.ua"
}

variable "cluster_issuer_name" {
  description = "Назва ClusterIssuer для cert-manager"
  type        = string
  default     = "letsencrypt-prod"
}

variable "cluster_name" {
  description = "Назва EKS кластера для auto-discovery Cluster Autoscaler"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN OIDC-провайдера EKS для IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL OIDC-провайдера EKS (без https://)"
  type        = string
}

variable "cluster_autoscaler_image_tag" {
  description = "Тег образу Cluster Autoscaler (має відповідати мінорній версії Kubernetes EKS)"
  type        = string
  default     = "v1.37.0"
}
