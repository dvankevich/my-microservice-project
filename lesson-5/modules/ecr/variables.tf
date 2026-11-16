variable "repository_name" {
  description = "Ім'я ECR-репозиторію (ECS і EKS шукають його за цим іменем)"
  type        = string
  default     = "lesson-5-ecr"
}
