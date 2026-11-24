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

#-------------VPC-----------------

output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.vpc.internet_gateway_id
}

#-------------EKS-----------------

output "eks_cluster_endpoint" {
  description = "EKS API endpoint for connecting to the cluster"
  value       = module.eks.eks_cluster_endpoint
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.eks_cluster_name
}

output "eks_node_role_arn" {
  description = "IAM role ARN for EKS Worker Nodes"
  value       = module.eks.eks_node_role_arn
}

#-------------Cluster Addons------

output "ingress_elb_hostname" {
  description = "AWS ELB hostname для налаштування DNS CNAME (django-app та jenkins)"
  value       = module.cluster_addons.ingress_elb_hostname
}

#-------------Jenkins-------------

output "jenkins_release" {
  description = "Ім'я Helm-релізу Jenkins"
  value       = module.jenkins.jenkins_release_name
}

output "jenkins_namespace" {
  description = "Namespace, у якому розгорнуто Jenkins"
  value       = module.jenkins.jenkins_namespace
}

output "jenkins_url" {
  description = "URL веб-інтерфейсу Jenkins"
  value       = module.jenkins.jenkins_url
}

#-------------Argo CD-------------

output "argocd_url" {
  description = "HTTPS URL веб-інтерфейсу Argo CD"
  value       = module.argo_cd.argocd_url
}

output "argocd_admin_password_command" {
  description = "Команда для отримання пароля адміністратора Argo CD"
  value       = module.argo_cd.admin_password_command
}

#------------ RDS ---------------
output "rds_endpoint" {
  description = "PostgreSQL writer endpoint"
  value       = module.rds.db_endpoint
}

output "rds_reader_endpoint" {
  description = "PostgreSQL reader endpoint"
  value       = module.rds.db_reader_endpoint
}

output "rds_port" {
  description = "PostgreSQL port"
  value       = module.rds.db_port
}

#-------------Monitoring----------

output "monitoring_namespace" {
  description = "Namespace, у якому розгорнуто Prometheus"
  value       = module.monitoring.monitoring_namespace
}

output "prometheus_service_url" {
  description = "Внутрішній кластерний URL Prometheus"
  value       = module.monitoring.prometheus_service_url
}

output "prometheus_port_forward_command" {
  description = "Команда для відкриття веб-інтерфейсу Prometheus"
  value       = module.monitoring.port_forward_command
}
