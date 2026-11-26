# Підключаємо модуль для S3 та DynamoDB
module "s3_backend" {
  source      = "./modules/s3-backend"   # Шлях до модуля
  bucket_name = "tfstate-bucket-lesson5" # Ім'я S3-бакета
}

# Підключаємо модуль для VPC
module "vpc" {
  source             = "./modules/vpc"                                     # Шлях до модуля VPC
  vpc_cidr_block     = "10.0.0.0/16"                                       # CIDR блок для VPC
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]       # Публічні підмережі
  private_subnets    = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]       # Приватні підмережі
  availability_zones = ["eu-central-1a", "eu-central-1b", "eu-central-1c"] # Зони доступності
  vpc_name           = "vpc"                                               # Ім'я VPC
}

# Підключаємо модуль ECR
module "ecr" {
  source      = "./modules/ecr" # Шлях до модуля
  environment = "dev"           # Середовище
}

# Підключаємо модуль EKS
module "eks" {
  source        = "./modules/eks"
  cluster_name  = "eks-cluster-demo"        # Назва кластера
  subnet_ids    = module.vpc.public_subnets # ID підмереж
  instance_type = "t3.small"                # Тип інстансів
  desired_size  = 5                         # Бажана кількість нодів
  max_size      = 6                         # Максимальна кількість нодів
  min_size      = 5                         # Мінімальна кількість нодів
}

# Отримуємо дані кластера EKS для провайдерів Helm та Kubernetes
data "aws_eks_cluster" "eks" {
  name       = module.eks.eks_cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "eks" {
  name       = module.eks.eks_cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

# Підключаємо кластерні аддони (Multi-AZ ingress-nginx + cert-manager + ClusterIssuer)
module "cluster_addons" {
  source                = "./modules/cluster-addons"
  ingress_replica_count = 2
  acme_email            = "admin@dvankevich.pp.ua"
  cluster_issuer_name   = "letsencrypt-prod"

  depends_on = [module.eks]
}

# Підключаємо модуль Jenkins з IRSA та динамічною адресою ECR
module "jenkins" {
  source             = "./modules/jenkins"
  cluster_name       = module.eks.eks_cluster_name
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  ecr_repository_url = module.ecr.repository_url
  storage_class_name = "ebs-gp3"
  jenkins_host       = "jenkins.dvankevich.pp.ua"

  depends_on = [
    module.eks,
    module.cluster_addons
  ]
}

# Підключаємо модуль Argo CD (GitOps CD)
module "argo_cd" {
  source             = "./modules/argo-cd"
  cluster_name       = module.eks.eks_cluster_name
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  namespace          = "argocd"
  argocd_host        = "argocd.dvankevich.pp.ua"
  ecr_repository_url = module.ecr.repository_url

  depends_on = [
    module.eks,
    module.cluster_addons
  ]
}

# Підключаємо модуль моніторингу (Prometheus)
module "monitoring" {
  source             = "./modules/monitoring"
  namespace          = "monitoring"
  storage_class_name = "ebs-gp3"
  storage_size       = "5Gi"
  retention          = "3d"
  ingress_enabled    = false

  depends_on = [module.eks, module.cluster_addons]
}

locals {
  django_secrets = try(
    yamldecode(file("${path.module}/charts/django-app/secrets.yaml")).secrets,
    {}
  )
  db_password = coalesce(
    try(local.django_secrets["POSTGRES_PASSWORD"], null),
    var.db_password
  )
}

# Бакет медіа Wagtail і IRSA-роль для ServiceAccount django у namespace wagtail
module "media_s3" {
  source = "./modules/media-s3"

  bucket_name       = "wagtail-media-lesson5"
  cluster_name      = module.eks.eks_cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "wagtail"
  service_account   = "django"
  cors_allowed_origins = [
    "https://django-app.dvankevich.pp.ua",
    "http://localhost:8000",
    "http://127.0.0.1:8000",
  ]

  depends_on = [module.eks]
}

module "rds" {
  source = "./modules/rds"

  name                 = "wagtail-db"
  use_aurora           = false # false = стандартна RDS (Free Tier); true = Aurora Cluster + writer
  aurora_replica_count = 0

  # --- RDS-only ---
  engine                     = "postgres"
  engine_version             = "16"
  parameter_group_family_rds = "postgres16"
  allocated_storage          = 20

  # --- Aurora-only ---
  engine_cluster                = "aurora-postgresql"
  engine_version_cluster        = "16.4"
  parameter_group_family_aurora = "aurora-postgresql16"

  # --- Спільні параметри ---
  instance_class          = "db.t3.micro"
  db_name                 = "wagtail"
  username                = "wagtail_user"
  password                = local.db_password
  vpc_id                  = module.vpc.vpc_id
  subnet_private_ids      = module.vpc.private_subnets
  subnet_public_ids       = module.vpc.public_subnets
  publicly_accessible     = false
  allowed_cidr_blocks     = ["10.0.0.0/16"]
  multi_az                = false
  backup_retention_period = 1
  skip_final_snapshot     = true

  parameters = {
    max_connections = "100"
    log_statement   = "ddl"
    work_mem        = "8192" # 8 МБ (значення в кілобайтах для PostgreSQL)
  }

  tags = {
    Environment = "dev"
    Project     = "wagtail-eks"
  }
}
