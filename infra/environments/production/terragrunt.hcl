include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules//platform"
}

inputs = {
  environment        = "production"
  cluster_name       = "rollbackops-production"
  kubernetes_version = "1.31"

  vpc_cidr           = "10.20.0.0/16"
  # AZ names are hardcoded for us-east-1 (the region set in root.hcl)
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.20.0.0/20", "10.20.16.0/20"]
  private_subnet_cidrs = ["10.20.128.0/20", "10.20.144.0/20"]
  single_nat_gateway   = false

  endpoint_public_access = true
  # TODO: replace with office/VPN CIDR
  public_access_cidrs = ["203.0.113.0/24"]

  node_instance_types = ["m5.large"]
  node_capacity_type  = "ON_DEMAND"
  node_min_size       = 2
  node_desired_size   = 2
  node_max_size       = 6

  ecr_force_delete      = false
  ecr_max_tagged_images = 30

  github_oidc_enabled = false
}
