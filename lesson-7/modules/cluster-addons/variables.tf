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
