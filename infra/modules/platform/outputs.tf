output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "oidc_issuer_url" {
  value = module.eks.oidc_issuer_url
}

output "node_role_arn" {
  value = module.iam.node_role_arn
}

output "ecr_repository_urls" {
  value = { for name, repo in module.ecr : name => repo.repository_url }
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
