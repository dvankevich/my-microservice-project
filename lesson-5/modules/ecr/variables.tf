variable "repository_name" {
  description = "Ім'я ECR-репозиторію"
  type        = string
  default     = "lesson-5-ecr"
}

variable "environment" {
  description = "Середовище (dev, stage, prod)"
  type        = string
}

variable "image_tag_mutability" {
  description = "MUTABLE або IMMUTABLE"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Сканувати образи при push"
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Дозволяти видалення репозиторію з образами"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Додаткові теги"
  type        = map(string)
  default     = {}
}
