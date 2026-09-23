# RollbackOps infrastructure (OpenTofu + Terragrunt)

## Layout

```
infra/
  modules/
    iam/       # EKS cluster + node IAM roles
    eks/       # EKS cluster, managed node group, addons, IRSA OIDC provider
    ecr/       # ECR repository + lifecycle policy (per repo, via for_each)
    platform/  # composition root: iam + eks + ecr — what each env deploys
  environments/
    root.hcl              # generated provider + backend, shared inputs
    staging/terragrunt.hcl
    production/terragrunt.hcl
```

## Mock vs real mode

`ROLLBACKOPS_MOCK_AWS` (default `"true"`) controls the generated AWS provider
block and backend:

- **mock**: static dummy credentials, all validation/metadata checks skipped,
  `local` backend under `.terragrunt-local-state/`. `init`, `validate` and
  `plan` work with zero AWS credentials. `apply` will NOT work.
- **real** (`ROLLBACKOPS_MOCK_AWS=false`): real credentials via the normal AWS
  chain, S3 backend `rollbackops-tfstate-<account-id>` with a DynamoDB lock
  table `rollbackops-tfstate-lock` in `us-east-1`. The bucket and table must
  exist before the first real `init` (or wire a `remote_state` block back in
  to let Terragrunt auto-create them — see the comment in `root.hcl`).

## Commands

```bash
# per environment
cd infra/environments/staging
terragrunt init
terragrunt validate
terragrunt plan

# or all envs from infra/environments/
terragrunt run-all plan
```

`terraform fmt` equivalent: `tofu fmt -recursive infra/` (CI checks it).

## Caveats

- The `vpc_id` / `subnet_ids` inputs are **placeholders** — a VPC module is
  the next step; EKS requires real subnets across 2+ AZs before `apply`.
- `production/public_access_cidrs` is the `203.0.113.0/24` documentation
  range — replace with the office/VPN CIDR.
- Provider lock files (`.terraform.lock.hcl`) are committed.

## Pushing images to ECR

```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
docker tag model-server:local <account>.dkr.ecr.us-east-1.amazonaws.com/rollbackops/model-server:v1.0.0
docker push <account>.dkr.ecr.us-east-1.amazonaws.com/rollbackops/model-server:v1.0.0
```

Tag releases with `v*` — the lifecycle policy keeps only the newest
`ecr_max_tagged_images` `v`-tagged images and expires untagged images after
`untagged_expiry_days` (7).
