variable "name" {
  description = "Назва Helm-релізу Argo CD"
  type        = string
  default     = "argo-cd"
}

variable "namespace" {
  description = "Kubernetes namespace для Argo CD"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Версія Helm-чарту argo-cd (null = останній стабільний реліз)"
  type        = string
  default     = null
}

variable "argocd_host" {
  description = "Доменне ім'я для веб-інтерфейсу Argo CD"
  type        = string
  default     = "argocd.dvankevich.pp.ua"
}
