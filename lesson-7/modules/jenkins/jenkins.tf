resource "helm_release" "jenkins" {
  name             = "jenkins"
  namespace        = var.namespace
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  create_namespace = true
  timeout          = 600

  values = [
    file("${path.module}/values.yaml")
  ]

  set {
    name  = "controller.admin.username"
    value = var.admin_username
  }

  set_sensitive {
    name  = "controller.admin.password"
    value = var.admin_password
  }

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
}
