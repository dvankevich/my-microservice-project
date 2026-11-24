# 1. Multi-AZ NGINX Ingress Controller (2 репліки в різних зонах доступності)
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  create_namespace = true
  timeout          = 600

  values = [
    yamlencode({
      controller = {
        replicaCount = var.ingress_replica_count
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "384Mi"
          }
        }
        topologySpreadConstraints = [
          {
            maxSkew           = 1
            topologyKey       = "topology.kubernetes.io/zone"
            whenUnsatisfiable = "ScheduleAnyway"
            labelSelector = {
              matchLabels = {
                "app.kubernetes.io/name"      = "ingress-nginx"
                "app.kubernetes.io/component" = "controller"
              }
            }
          }
        ]
      }
    })
  ]
}

# Кластерний StorageClass для AWS EBS (gp3 із шифруванням)
resource "kubernetes_storage_class_v1" "ebs_gp3" {
  metadata {
    name = "ebs-gp3"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}


# 2. Cert-Manager із встановленням CRD
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  create_namespace = true
  timeout          = 600

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

# 3. Production ACME ClusterIssuer (Let's Encrypt)
resource "kubernetes_manifest" "letsencrypt_prod" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = var.cluster_issuer_name
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "${var.cluster_issuer_name}-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

# Отримуємо DNS-ім'я створеного AWS LoadBalancer для виводу в Terraform
data "kubernetes_service_v1" "ingress_nginx_controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = helm_release.ingress_nginx.namespace
  }

  depends_on = [helm_release.ingress_nginx]
}
