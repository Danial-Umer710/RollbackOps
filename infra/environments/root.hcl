locals {
  # Mock mode (default): fake static credentials + local backend, so
  # `terragrunt init/validate/plan` work with no AWS access at all.
  # Set ROLLBACKOPS_MOCK_AWS=false for real AWS operations.
  mock_aws   = get_env("ROLLBACKOPS_MOCK_AWS", "true") == "true"
  aws_region = "us-east-1"

  backend_local = <<-EOF
    terraform {
      backend "local" {
        path = "${replace(get_terragrunt_dir(), "\\", "/")}/.terragrunt-local-state/terraform.tfstate"
      }
    }
  EOF

  backend_s3 = <<-EOF
    terraform {
      backend "s3" {
        bucket         = "rollbackops-tfstate-${local.mock_aws ? "0" : get_aws_account_id()}"
        key            = "${path_relative_to_include()}/terraform.tfstate"
        region         = "${local.aws_region}"
        encrypt        = true
        dynamodb_table = "rollbackops-tfstate-lock"
      }
    }
  EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"
      %{~ if local.mock_aws ~}
      access_key                  = "mock"
      secret_key                  = "mock"
      skip_credentials_validation = true
      skip_requesting_account_id  = true
      skip_metadata_api_check     = true
      skip_region_validation      = true
      %{~ endif ~}
      default_tags {
        tags = {
          Project   = "RollbackOps"
          ManagedBy = "opentofu-terragrunt"
        }
      }
    }
  EOF
}

# The remote_state block can't switch `config` between local and s3 shapes
# (HCL conditional requires identical object types), so the backend is
# generated directly. In real mode create the S3 bucket + DynamoDB lock
# table beforehand (or switch back to remote_state for auto-creation).
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = local.mock_aws ? local.backend_local : local.backend_s3
}

inputs = {
  region = local.aws_region
}
