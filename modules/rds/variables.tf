variable "name" {
  description = "Базове ім'я інстансу або кластера БД"
  type        = string
}

variable "use_aurora" {
  description = "Перемикач архітектури: true — Amazon Aurora Cluster, false — стандартний RDS instance"
  type        = bool
  default     = false
}

# --- Параметри для стандартної RDS (use_aurora = false) ---
variable "engine" {
  description = "Движок бази даних для стандартної RDS (postgres, mysql, mariadb тощо)"
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  description = "Версія движка для стандартної RDS (мажорна або повна, наприклад 16 або 17.2)"
  type        = string
  default     = "16"
}

variable "parameter_group_family_rds" {
  description = "Сімейство параметрів для стандартної RDS (має відповідати engine_version)"
  type        = string
  default     = "postgres16"
}

variable "allocated_storage" {
  description = "Обсяг сховища в ГБ для стандартної RDS"
  type        = number
  default     = 20
}

# --- Параметри для Amazon Aurora (use_aurora = true) ---
variable "engine_cluster" {
  description = "Движок кластера Aurora (aurora-postgresql або aurora-mysql)"
  type        = string
  default     = "aurora-postgresql"
}

variable "engine_version_cluster" {
  description = "Версія движка для кластера Aurora (наприклад, 16.4 або 15.8)"
  type        = string
  default     = "16.4"
}

variable "parameter_group_family_aurora" {
  description = "Сімейство кластерних параметрів для Aurora (має відповідати engine_version_cluster)"
  type        = string
  default     = "aurora-postgresql16"
}

variable "aurora_replica_count" {
  description = "Кількість read-only реплік Aurora на додачу до writer-інстансу (0 — лише writer)"
  type        = number
  default     = 0
}

# --- Спільні параметри інстансів та БД ---
variable "instance_class" {
  description = "Клас інстансу БД (db.t3.micro для Free Tier; db.t3.medium або db.r6g.large для Aurora)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Ім'я початкової бази даних"
  type        = string
}

variable "username" {
  description = "Ім'я адміністративного користувача БД"
  type        = string
}

variable "password" {
  description = "Пароль адміністративного користувача БД"
  type        = string
  sensitive   = true
}

variable "multi_az" {
  description = "Увімкнення Multi-AZ розгортання для стандартної RDS"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Кількість днів зберігання автоматичних резервних копій (0 — вимкнено)"
  type        = number
  default     = 1
}

variable "skip_final_snapshot" {
  description = "Пропускати створення фінального снепшоту під час видалення БД (рекомендовано true для dev/test)"
  type        = bool
  default     = true
}

# --- Мережа та безпека ---
variable "vpc_id" {
  description = "ID VPC, у якій розгортається база даних"
  type        = string
}

variable "subnet_private_ids" {
  description = "Список ID приватних підмереж для DB Subnet Group"
  type        = list(string)
}

variable "subnet_public_ids" {
  description = "Список ID публічних підмереж (використовуються, якщо publicly_accessible = true)"
  type        = list(string)
}

variable "publicly_accessible" {
  description = "Чи має БД отримувати публічну IP-адресу (false — ізоляція у приватних підмережах)"
  type        = bool
  default     = false
}

variable "db_port" {
  description = "TCP-порт підключення до бази даних (5432 для PostgreSQL, 3306 для MySQL)"
  type        = number
  default     = 5432
}

variable "allowed_cidr_blocks" {
  description = "Список CIDR-блоків, яким дозволено підключення до БД"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

# --- Параметри конфігурації СКБД ---
variable "parameters" {
  description = "Словник параметрів для DB/Cluster Parameter Group (work_mem для PostgreSQL вказується в КБ)"
  type        = map(string)
  default = {
    max_connections = "100"
    log_statement   = "ddl"
    work_mem        = "8192"
  }
}

variable "tags" {
  description = "Теги, що додаються до всіх ресурсів модуля"
  type        = map(string)
  default     = {}
}
