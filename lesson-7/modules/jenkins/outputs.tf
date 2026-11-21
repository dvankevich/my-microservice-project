output "jenkins_release_name" {
  description = "Назва Helm-релізу Jenkins"
  value       = helm_release.jenkins.name
}

output "jenkins_namespace" {
  description = "Namespace, у якому розгорнуто Jenkins"
  value       = helm_release.jenkins.namespace
}

output "jenkins_url" {
  description = "URL веб-інтерфейсу Jenkins"
  value       = "https://${var.jenkins_host}"
}
