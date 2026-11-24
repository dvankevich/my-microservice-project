variable "db_password" {
  description = "Master password for AWS RDS / Aurora PostgreSQL"
  type        = string
  sensitive   = true
  default     = null
}
