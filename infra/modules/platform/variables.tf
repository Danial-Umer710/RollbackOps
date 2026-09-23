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

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
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
