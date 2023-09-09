
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_autoscaler_role_arn" {
  value = module.cluster_autoscaler_irsa_role.iam_role_arn
}

output "cluster_secretstore_role_arn" {
  value = module.cluster_secretstore_role.iam_role_arn
}
