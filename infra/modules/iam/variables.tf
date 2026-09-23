variable "name_prefix" {
  description = "Prefix for IAM role names"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
