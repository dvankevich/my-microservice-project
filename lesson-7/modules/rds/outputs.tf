output "db_endpoint" {
  description = "Endpoint для запису/читання (RDS instance або Aurora cluster writer endpoint)"
  value       = var.use_aurora ? aws_rds_cluster.aurora[0].endpoint : aws_db_instance.standard[0].address
}

output "db_reader_endpoint" {
  description = "Read-only endpoint (для Aurora — reader_endpoint, для RDS — основний endpoint)"
  value       = var.use_aurora ? aws_rds_cluster.aurora[0].reader_endpoint : aws_db_instance.standard[0].address
}

output "db_port" {
  description = "Порт підключення до бази даних"
  value       = var.use_aurora ? aws_rds_cluster.aurora[0].port : aws_db_instance.standard[0].port
}

output "db_name" {
  description = "Ім'я бази даних"
  value       = var.db_name
}

output "security_group_id" {
  description = "ID створеної Security Group"
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  description = "Назва створеної DB Subnet Group"
  value       = aws_db_subnet_group.default.name
}
