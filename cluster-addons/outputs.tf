output "storage_class" {
  description = "Name of the default StorageClass."
  value       = kubernetes_storage_class_v1.gp3.metadata[0].name
}

output "lb_controller_version" {
  description = "Deployed aws-load-balancer-controller chart version."
  value       = helm_release.aws_load_balancer_controller.version
}
