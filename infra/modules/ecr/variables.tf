variable "repository_name" {
  type = string
}

variable "image_tag_mutability" {
  type    = string
  default = "IMMUTABLE"
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE"
  }
}

variable "scan_on_push" {
  type    = bool
  default = true
}

variable "force_delete" {
  type    = bool
  default = false
}

variable "untagged_expiry_days" {
  type    = number
  default = 7
}

variable "max_tagged_images" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
