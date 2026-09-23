include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules//platform"
}

inputs = {
  environment        = "staging"
  cluster_name       = "rollbackops-staging"
  kubernetes_version = "1.31"

  vpc_cidr           = "10.10.0.0/16"
  # AZ names are hardcoded for us-east-1 (the region set in root.hcl)
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.10.0.0/20", "10.10.16.0/20"]
  private_subnet_cidrs = ["10.10.128.0/20", "10.10.144.0/20"]
  single_nat_gateway   = true

  endpoint_public_access = true
  public_access_cidrs    = ["0.0.0.0/0"]

  node_instance_types = ["t3.medium"]
  node_capacity_type  = "SPOT"
  node_min_size       = 1
  node_desired_size   = 1
  node_max_size       = 3

  ecr_force_delete      = true
  ecr_max_tagged_images = 10

  # GitHub's OIDC provider is one-per-AWS-account; created here only.
  github_oidc_enabled = true
}
