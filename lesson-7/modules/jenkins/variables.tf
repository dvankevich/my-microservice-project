variable "cluster_name" {
  description = "Назва EKS кластера"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace для Jenkins"
  type        = string
  default     = "jenkins"
}

variable "storage_class_name" {
  description = "Ім'я StorageClass для збереження даних Jenkins"
  type        = string
  default     = "ebs-gp3"
}

variable "storage_size" {
  description = "Розмір EBS-тому для /var/jenkins_home"
  type        = string
  default     = "10Gi"
}

variable "jenkins_host" {
  description = "Доменне ім'я для доступу до Jenkins через Ingress"
  type        = string
  default     = "jenkins.dvankevich.pp.ua"
}

variable "admin_username" {
  description = "Логін адміністратора Jenkins"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Пароль адміністратора Jenkins"
  type        = string
  sensitive   = true
}
