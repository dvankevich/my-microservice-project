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

variable "image_updater_chart_version" {
  description = "Версія Helm-чарту argocd-image-updater (null = останній стабільний реліз)"
  type        = string
  default     = null
}

variable "argocd_host" {
  description = "Доменне ім'я для веб-інтерфейсу Argo CD"
  type        = string
  default     = "argocd.dvankevich.pp.ua"
}

variable "ecr_repository_url" {
  description = "Повний URL репозиторію Amazon ECR"
  type        = string
}

variable "aws_region" {
  description = "Регіон AWS для авторизації в Amazon ECR"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Назва EKS кластера"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN OIDC-провайдера EKS для IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL OIDC-провайдера EKS для IRSA"
  type        = string
}
