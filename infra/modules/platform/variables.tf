variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "single_nat_gateway" {
  type    = bool
  default = false
}

variable "github_repository" {
  type    = string
  default = "Danial-Umer710/RollbackOps"
}

variable "github_oidc_enabled" {
  description = "Create the GitHub Actions OIDC provider + ECR push role (one provider per AWS account)"
  type        = bool
  default     = false
}

variable "rollback_controller_namespace" {
  type    = string
  default = "default"
}

variable "rollback_controller_service_account" {
  type    = string
  default = "rollback-controller"
}

variable "endpoint_public_access" {
  type    = bool
  default = true
}

variable "public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "node_min_size" {
  type = number
}

variable "node_desired_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "ecr_repositories" {
  type    = list(string)
  default = ["model-server", "drift-detector", "rollback-controller"]
}

variable "ecr_force_delete" {
  type    = bool
  default = false
}

variable "ecr_max_tagged_images" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
