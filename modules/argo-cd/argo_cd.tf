locals {
  ecr_registry   = split("/", var.ecr_repository_url)[0]
  ecr_secret_cmd = <<-EOT
    kubectl create secret docker-registry ecr-credentials \
      --namespace ${var.namespace} \
      --docker-server=${local.ecr_registry} \
      --docker-username=AWS \
      --docker-password="$(cat /token/ecr-password)" \
      --dry-run=client -o yaml | kubectl apply -f -
  EOT
}

resource "helm_release" "argo_cd" {
  name             = var.name
  namespace        = var.namespace
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  create_namespace = true
  timeout          = 600

  values = [
    file("${path.module}/values.yaml")
  ]

  set {
    name  = "server.ingress.hostname"
    value = var.argocd_host
  }
}

# IAM-роль для отримання токена авторизації Amazon ECR (IRSA)
resource "aws_iam_role" "argocd_ecr_role" {
  name = "${var.cluster_name}-argocd-ecr-role"

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
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:ecr-token-refresher"
            "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "argocd_ecr_policy" {
  name = "${var.cluster_name}-argocd-ecr-policy"
  role = aws_iam_role.argocd_ecr_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      }
    ]
  })
}

# ServiceAccount та права виключно на керування секретом ecr-credentials у namespace argocd
resource "kubernetes_service_account_v1" "ecr_token_refresher" {
  metadata {
    name      = "ecr-token-refresher"
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.argocd_ecr_role.arn
    }
  }

  depends_on = [
    helm_release.argo_cd,
    aws_iam_role_policy.argocd_ecr_policy
  ]
}

resource "kubernetes_role_v1" "ecr_token_refresher" {
  metadata {
    name      = "ecr-token-refresher"
    namespace = var.namespace
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "get", "patch", "update"]
  }

  depends_on = [helm_release.argo_cd]
}

resource "kubernetes_role_binding_v1" "ecr_token_refresher" {
  metadata {
    name      = "ecr-token-refresher"
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.ecr_token_refresher.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ecr_token_refresher.metadata[0].name
    namespace = var.namespace
  }
}

# Одноразовий запуск при terraform apply, щоб токен ECR був готовий одразу
resource "kubernetes_job_v1" "ecr_token_init" {
  metadata {
    name      = "ecr-token-init"
    namespace = var.namespace
  }

  spec {
    ttl_seconds_after_finished = 120
    template {
      metadata {}
      spec {
        service_account_name = kubernetes_service_account_v1.ecr_token_refresher.metadata[0].name
        restart_policy       = "OnFailure"

        init_container {
          name    = "get-ecr-token"
          image   = "public.ecr.aws/aws-cli/aws-cli:latest"
          command = ["/bin/sh", "-c", "aws ecr get-login-password --region ${var.aws_region} > /token/ecr-password"]

          volume_mount {
            name       = "token-dir"
            mount_path = "/token"
          }
        }

        container {
          name    = "update-secret"
          image   = "alpine/kubectl:latest"
          command = ["/bin/sh", "-c", local.ecr_secret_cmd]

          volume_mount {
            name       = "token-dir"
            mount_path = "/token"
          }
        }

        volume {
          name = "token-dir"
          empty_dir {}
        }
      }
    }
  }

  wait_for_completion = true

  depends_on = [
    kubernetes_service_account_v1.ecr_token_refresher,
    kubernetes_role_binding_v1.ecr_token_refresher
  ]
}

# Періодичне оновлення токена ECR (діє 12 год, оновлюємо кожні 6 год)
resource "kubernetes_cron_job_v1" "ecr_token_refresh" {
  metadata {
    name      = "ecr-token-refresh"
    namespace = var.namespace
  }

  spec {
    schedule                      = "0 */6 * * *"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 1

    job_template {
      metadata {}
      spec {
        ttl_seconds_after_finished = 120
        template {
          metadata {}
          spec {
            service_account_name = kubernetes_service_account_v1.ecr_token_refresher.metadata[0].name
            restart_policy       = "OnFailure"

            init_container {
              name    = "get-ecr-token"
              image   = "public.ecr.aws/aws-cli/aws-cli:latest"
              command = ["/bin/sh", "-c", "aws ecr get-login-password --region ${var.aws_region} > /token/ecr-password"]

              volume_mount {
                name       = "token-dir"
                mount_path = "/token"
              }
            }

            container {
              name    = "update-secret"
              image   = "alpine/kubectl:latest"
              command = ["/bin/sh", "-c", local.ecr_secret_cmd]

              volume_mount {
                name       = "token-dir"
                mount_path = "/token"
              }
            }

            volume {
              name = "token-dir"
              empty_dir {}
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_job_v1.ecr_token_init]
}

# Контролер Argo CD Image Updater
resource "helm_release" "argocd_image_updater" {
  name             = "argocd-image-updater"
  namespace        = var.namespace
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argocd-image-updater"
  version          = var.image_updater_chart_version
  create_namespace = false
  timeout          = 600

  values = [
    templatefile("${path.module}/image-updater-values.yaml", {
      ecr_registry = local.ecr_registry
      namespace    = var.namespace
    })
  ]

  depends_on = [kubernetes_job_v1.ecr_token_init]
}

resource "helm_release" "argo_apps" {
  name             = "${var.name}-apps"
  chart            = "${path.module}/charts"
  namespace        = var.namespace
  create_namespace = false

  values = [
    templatefile("${path.module}/charts/values.yaml", {
      ecr_repository_url = var.ecr_repository_url
    })
  ]

  depends_on = [
    helm_release.argo_cd,
    helm_release.argocd_image_updater
  ]
}
