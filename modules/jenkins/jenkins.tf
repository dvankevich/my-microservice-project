# 1. IAM-роль для подів-агентів Kaniko (IRSA)
resource "aws_iam_role" "jenkins_kaniko_role" {
  name = "${var.cluster_name}-jenkins-kaniko-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:jenkins-sa"
            "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# 2. Політика доступу до Amazon ECR для збірки та пушу образів
resource "aws_iam_role_policy" "jenkins_ecr_policy" {
  name = "${var.cluster_name}-jenkins-kaniko-ecr-policy"
  role = aws_iam_role.jenkins_kaniko_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories"
        ]
        Resource = "*"
      }
    ]
  })
}

# 3. Namespace та ServiceAccount створюються ДО релізу Helm
resource "kubernetes_namespace_v1" "jenkins" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_service_account_v1" "jenkins_sa" {
  metadata {
    name      = "jenkins-sa"
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.jenkins_kaniko_role.arn
    }
  }
}

# 4. Helm-реліз Jenkins (об'єднує публічний values.yaml та локальний secrets.yaml)
resource "helm_release" "jenkins" {
  name             = "jenkins"
  namespace        = kubernetes_namespace_v1.jenkins.metadata[0].name
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  create_namespace = false
  timeout          = 600

  values = [
    templatefile("${path.module}/values.yaml", {
      ecr_repository_url = var.ecr_repository_url
    }),
    file("${path.module}/secrets.yaml")
  ]

  set {
    name  = "controller.ingress.hostName"
    value = var.jenkins_host
  }

  set {
    name  = "persistence.storageClass"
    value = var.storage_class_name
  }

  set {
    name  = "persistence.size"
    value = var.storage_size
  }

  depends_on = [
    kubernetes_service_account_v1.jenkins_sa,
    aws_iam_role_policy.jenkins_ecr_policy
  ]
}
