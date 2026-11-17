output "s3_bucket_name" {
  description = "Назва S3-бакета для стейтів"
  value       = module.s3_backend.s3_bucket_name
}

# output "dynamodb_table_name" {
#   description = "Назва таблиці DynamoDB для блокування стейтів"
#   value       = module.s3_backend.dynamodb_table_name
# }

output "nat_gateway_id" {
  description = "ID спільного NAT Gateway у VPC"
  value       = module.vpc.nat_gateway_id
}

output "repository_url" {
  description = "URL створеного репозиторію Amazon ECR"
  value       = module.ecr.repository_url
}
