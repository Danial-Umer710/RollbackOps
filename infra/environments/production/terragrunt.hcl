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

  # TODO: replace with VPC module output
  vpc_id     = "vpc-0production0placeholder"
  subnet_ids = ["subnet-0production0a", "subnet-0production0b", "subnet-0production0c"]

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
}
