variable "name" {
  type = string
}

variable "cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type = list(string)
  # EKS requires subnets in at least 2 AZs
  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "availability_zones must contain exactly 2 AZs (EKS requires >= 2)"
  }
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "cluster_name" {
  description = "Used for kubernetes.io/cluster/<name> subnet tags"
  type        = string
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

variable "single_nat_gateway" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
