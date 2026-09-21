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
- **State management** — commented S3 + DynamoDB remote-state backend ready to enable

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

# 5. Tear everything down when done
terraform destroy -var="environment=dev"
```

Copy `terraform.tfvars.example` to `terraform.tfvars` to persist your variables.

## Project structure

```
├── main.tf                  # provider + module composition
├── variables.tf             # root inputs (region, env, CIDR, AZs, ASG sizing)
├── outputs.tf               # vpc_id, alb_dns_name, application_url
├── versions.tf              # Terraform + provider pins, remote-state template
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
