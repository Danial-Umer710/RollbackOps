# RollbackOps infrastructure (OpenTofu + Terragrunt)

## Layout

```
infra/
  modules/
    vpc/             # VPC, public/private subnets, IGW + NAT, route tables
    iam/             # EKS cluster + node IAM roles
    eks/             # EKS cluster, managed node group, addons, IRSA OIDC provider
    ecr/             # ECR repository + lifecycle policy (per repo, via for_each)
    iam-irsa/        # IRSA role for a k8s ServiceAccount (sub+aud conditions)
    iam-github-oidc/ # GitHub Actions OIDC provider + ECR push role
    platform/        # composition root: vpc + iam + eks + ecr + irsa + github oidc
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

## VPC layout

Each env gets a dedicated VPC: public `/20` subnets (IGW route,
`kubernetes.io/role/elb` tags) and private `/20` subnets (NAT route,
`kubernetes.io/role/internal-elb`) across 2 AZs — staging `10.10.0.0/16`,
production `10.20.0.0/16`. EKS control-plane ENIs and the node group both use
the private subnets.

NAT cost note: staging uses `single_nat_gateway = true` (one NAT + EIP,
~$32/mo); production runs one NAT per AZ for HA (~$32/mo each). Set
`enable_nat_gateway = false` on the vpc module to skip entirely (nodes then
can't reach the internet).

## IRSA (rollback-controller)

The platform creates an IAM role `${cluster_name}-rollback-controller` trusted
via the cluster's OIDC provider for `system:serviceaccount:default:rollback-controller`
(baseline policy: AmazonS3ReadOnlyAccess — replace with a scoped policy when
the controller needs real AWS access). After `apply`, annotate the SA:

```bash
kubectl annotate sa rollback-controller \
  eks.amazonaws.com/role-arn=$(terragrunt output -raw rollback_controller_irsa_role_arn)
```

(or use the `rollback_controller_sa_annotation` output map directly in a
k8s manifest/helm values file).

## GitHub Actions ECR push

`github_oidc_enabled = true` (staging only — the `token.actions.githubusercontent.com`
provider is one-per-AWS-account) creates a role that CI can assume via OIDC to
push images to the three `rollbackops/*` ECR repos. To enable the
`build-and-push-ecr` CI job: apply staging, then set repo variables
`AWS_REGION` and `AWS_ECR_PUSH_ROLE_ARN` (the `github_actions_role_arn`
output), and flip the job's `if: false` to the condition in its comment.

## Caveats

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
