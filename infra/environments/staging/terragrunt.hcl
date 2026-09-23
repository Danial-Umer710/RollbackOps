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

  # TODO: replace with VPC module output
  vpc_id     = "vpc-0staging0placeholder"
  subnet_ids = ["subnet-0staging0a", "subnet-0staging0b"]

  endpoint_public_access = true
  public_access_cidrs    = ["0.0.0.0/0"]

  node_instance_types = ["t3.medium"]
  node_capacity_type  = "SPOT"
  node_min_size       = 1
  node_desired_size   = 1
  node_max_size       = 3

  ecr_force_delete      = true
  ecr_max_tagged_images = 10
}
