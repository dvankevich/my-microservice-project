variable "bucket_name" {
  description = "Глобально унікальна назва S3-бакета для зображень і документів Wagtail"
  type        = string
}

variable "cluster_name" {
  description = "Назва EKS-кластера. Входить в ім'я IAM-ролі IRSA"
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

variable "namespace" {
  description = "Kubernetes namespace, у якому працює ServiceAccount застосунку"
  type        = string
  default     = "wagtail"
}

variable "service_account" {
  description = "Ім'я ServiceAccount, якому дозволено писати в бакет"
  type        = string
  default     = "django"
}

variable "name_suffix" {
  description = "Суфікс IAM-ролі. Порожній залишає ім'я <cluster>-django-media."
  type        = string
  default     = ""
}

variable "environment" {
  description = "Тег Environment на бакеті"
  type        = string
  default     = "dev"
}

variable "cors_allowed_origins" {
  description = "Origin-и, з яких адмінка Wagtail може читати зображення (focal point)"
  type        = list(string)
  default     = []
}
