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

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "rollback_controller_irsa_role_arn" {
  value = module.rollback_controller_irsa.role_arn
}

output "rollback_controller_sa_annotation" {
  value = module.rollback_controller_irsa.service_account_annotation
}

output "github_actions_role_arn" {
  value = var.github_oidc_enabled ? module.github_oidc[0].role_arn : null
}
