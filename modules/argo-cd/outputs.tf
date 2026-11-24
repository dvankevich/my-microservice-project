output "argocd_url" {
  description = "HTTPS URL веб-інтерфейсу Argo CD"
  value       = "https://${var.argocd_host}"
}

output "admin_password_command" {
  description = "Команда для отримання початкового пароля користувача admin"
  value       = "kubectl -n ${var.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
}
