# Terraform AWS Infrastructure

Production-style AWS infrastructure written as reusable Terraform modules: a
multi-AZ VPC, least-privilege security groups, and an auto-scaled web tier
behind an Application Load Balancer. Every push is checked by GitHub Actions
(`terraform fmt`, `init`, `validate`).

## Architecture

```
                        ┌─────────────────────────────┐
                        │        AWS Region           │
                        │                             │
  Internet ──▶ │  Application Load Balancer  │ ──▶ │ Auto Scaling Group (EC2 + nginx) │
                        │   (public subnets, 2 AZs)   │     │  (launch template, health checks)  │
                        └─────────────────────────────┘
                        │        VPC 10.0.0.0/16      │
                        │  public subnets: 10.0.0.0/24, 10.0.1.0/24   │
                        │  private subnets: 10.0.10.0/24, 10.0.11.0/24 │
                        │  IGW + NAT gateway, per-tier route tables   │
                        └─────────────────────────────┘
```

Security groups follow least privilege: instances accept HTTP **only** from the
ALB security group — no direct internet access to the instances.

## What gets provisioned

| Module             | Resources |
|--------------------|-----------|
| `modules/vpc`      | VPC, 2 public + 2 private subnets across 2 AZs, internet gateway, NAT gateway, route tables |
| `modules/security-groups` | ALB security group (80/443), instance security group (HTTP from ALB only) |
| `modules/compute`  | ALB + listener + target group, launch template (Amazon Linux 2023, nginx via user data), Auto Scaling group |

## Skills demonstrated

- **Infrastructure as Code** — Terraform ≥ 1.5, AWS provider v5, reusable modules with typed variables and outputs
- **AWS networking** — VPC design, subnetting with `cidrsubnet`, IGW/NAT, route tables
- **Compute & scaling** — launch templates, Auto Scaling groups, ALB health checks
- **Security** — least-privilege security groups, no hardcoded secrets
- **CI/CD** — GitHub Actions pipeline running `fmt`, `init`, and `validate` on every push/PR
- **State management** — opt-in S3 + DynamoDB remote-state backend shipped as an example

## Usage

```bash
# 1. Configure AWS credentials (env vars, SSO, or shared config)
export AWS_PROFILE=my-profile

# 2. Initialise and review the plan
terraform init
terraform plan -var="environment=dev"

# 3. Apply (creates real AWS resources — see cost note below)
terraform apply -var="environment=dev"

# 4. Visit the app
terraform output application_url

# 5. Tear everything down when done (disable ALB deletion protection first, it defaults to true)
terraform apply -var="environment=dev" -var="alb_deletion_protection=false"
terraform destroy -var="environment=dev" -var="alb_deletion_protection=false"
```

Copy `terraform.tfvars.example` to `terraform.tfvars` to persist your variables.

## Remote state

Local `terraform.tfstate` files are fine for a solo demo, but teams store
state remotely so it is shared, locked, and durable. This repo ships
[`backend.tf.example`](backend.tf.example) -- copy it to `backend.tf` to opt in:

```bash
# 1. Create the state bucket once and turn on versioning
aws s3api create-bucket --bucket my-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket my-terraform-state \
  --versioning-configuration Status=Enabled

# 2. (Classic locking) create a DynamoDB table, partition key LockID (String)
aws dynamodb create-table --table-name terraform-state-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1

# 3. Copy the example, edit the placeholders, and migrate your state
cp backend.tf.example backend.tf   # edit bucket/region/locking first
terraform init                     # answer "yes" to copy existing state
```

Use a separate `key` per environment (`dev.tfstate`, `prod.tfstate`) so
environments never share a state file. `backend.tf` itself is gitignored,
only the example is committed. (S3-native locking via `use_lockfile = true`
is commented in the example as an alternative to DynamoDB, for AWS provider
5.51 and newer.)

## Project structure

```
├── main.tf                  # provider + module composition
├── backend.tf.example       # optional S3 + DynamoDB remote state (copy to backend.tf)
├── variables.tf             # root inputs (region, env, CIDR, AZs, ASG sizing, ALB deletion protection)
├── outputs.tf               # vpc_id, alb_dns_name, application_url
├── versions.tf              # Terraform + provider pins
├── modules/
│   ├── vpc/                 # VPC, subnets, IGW, NAT, route tables
│   ├── security-groups/     # ALB + instance security groups
│   └── compute/             # ALB, target group, launch template, ASG
├── .github/workflows/       # Terraform CI (fmt / init / validate)
└── terraform.tfvars.example
```

## Cost note

Defaults use `t3.micro` instances and a single NAT gateway (dev-friendly).
The NAT gateway is the main cost driver (~$30/month) — set
`enable_nat_gateway = false` in the VPC module call if you only need a
short-lived demo, and always run `terraform destroy` when finished.

## Roadmap

- [ ] Remote state backend (S3 + DynamoDB) enabled
- [ ] HTTPS listener with ACM certificate
- [ ] RDS module in private subnets
- [ ] `tflint` and `checkov` in CI
