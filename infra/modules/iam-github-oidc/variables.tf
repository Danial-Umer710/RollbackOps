variable "github_repository" {
  description = "owner/repo, e.g. Danial-Umer710/RollbackOps"
  type        = string
}

variable "allowed_refs" {
  type    = list(string)
  default = ["refs/heads/main"]
}

variable "role_name" {
  type    = string
  default = "rollbackops-github-actions-ecr-push"
}

variable "ecr_repository_arns" {
  type = list(string)
}

variable "create_oidc_provider" {
  type    = bool
  default = true
}

variable "oidc_provider_arn" {
  description = "Existing provider ARN when create_oidc_provider is false (one per AWS account)"
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
