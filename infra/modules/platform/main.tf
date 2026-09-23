locals {
  tags = merge(
    {
      Project     = "RollbackOps"
      Environment = var.environment
      ManagedBy   = "opentofu-terragrunt"
    },
    var.tags,
  )
}

module "iam" {
  source = "../iam"

  name_prefix = var.cluster_name
  tags        = local.tags
}

module "vpc" {
  source = "../vpc"

  name                 = var.cluster_name
  cluster_name         = var.cluster_name
  cidr_block           = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway

  tags = local.tags
}

module "eks" {
  source = "../eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  cluster_role_arn   = module.iam.cluster_role_arn
  node_role_arn      = module.iam.node_role_arn

  # Control-plane ENIs and nodes both land on the private subnets
  subnet_ids             = module.vpc.private_subnet_ids
  node_subnet_ids        = module.vpc.private_subnet_ids
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size
  node_labels         = { "rollbackops.io/environment" = var.environment }

  tags = local.tags
}

module "ecr" {
  source   = "../ecr"
  for_each = toset(var.ecr_repositories)

  repository_name   = "rollbackops/${each.key}"
  force_delete      = var.ecr_force_delete
  max_tagged_images = var.ecr_max_tagged_images
  tags              = local.tags
}

module "rollback_controller_irsa" {
  source = "../iam-irsa"

  role_name            = "${var.cluster_name}-rollback-controller"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_issuer_url      = module.eks.oidc_issuer_url
  namespace            = var.rollback_controller_namespace
  service_account_name = var.rollback_controller_service_account
  # Baseline read-only policy to prove IRSA; replace with a scoped policy
  # when the controller needs real AWS access.
  policy_arns = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]

  tags = local.tags
}

module "github_oidc" {
  source = "../iam-github-oidc"
  count  = var.github_oidc_enabled ? 1 : 0

  github_repository   = var.github_repository
  ecr_repository_arns = [for r in module.ecr : r.repository_arn]

  tags = local.tags
}
