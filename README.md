# Terraform AWS Infrastructure

Production-style AWS infrastructure written as reusable Terraform modules: a
multi-AZ VPC, least-privilege security groups, and an auto-scaled web tier
behind an Application Load Balancer. Every push is checked by GitHub Actions
(`terraform fmt`, `init`, `validate`).

## Architecture

Request path (what happens on every page load):

```
Internet (users)
  |
  v  HTTP :80
ALB -- public subnets, spans AZ-a + AZ-b
  Listener :80 -> target group :80, health check GET / on :80
  ALB SG: 80/443 in from 0.0.0.0/0; deletion protection on (default)
  |
  v  HTTP :80 -- instance SG allows HTTP only from the ALB SG
ASG -- EC2 + nginx (Amazon Linux 2023, launch template)
  min 1 / desired 2 / max 3, t3.micro (defaults)
  Target tracking: ASG average CPU -> 60% (default)
  Placement: public subnets in both AZs
```

VPC layout:

```
VPC 10.0.0.0/16 (us-east-1)
  |
  +-- AZ-a (us-east-1a)
  |     Public  10.0.0.0/24  -- ALB, ASG instances, NAT gateway + EIP
  |     Private 10.0.10.0/24 -- provisioned, no workloads yet
  |
  +-- AZ-b (us-east-1b)
        Public  10.0.1.0/24  -- ALB, ASG instances
        Private 10.0.11.0/24 -- provisioned, no workloads yet

Routes:  public  0.0.0.0/0 -> internet gateway
         private 0.0.0.0/0 -> NAT gateway (single, in the AZ-a public subnet)

Monitoring: ASG avg CPU > threshold (80% default) for 2 x 5 min -> CloudWatch alarm
            -> SNS topic -> email (only when notification_email is set)
```

Notes:

- The private subnets are provisioned but empty: the ASG runs in the
  public subnets today. They are reserved for the planned RDS module,
  which is why the NAT gateway exists before anything uses it.
- The ALB security group already allows 443, but there is no HTTPS
  listener yet (see the Roadmap). Opening the port now means adding
  the ACM listener later needs no security-group change.
- There is one NAT gateway, in AZ-a. If AZ-a fails, the private
  subnets lose outbound internet until it recovers. A per-AZ NAT
  gateway would fix that at roughly double the NAT cost.
- ALB access logs are off by default; see "ALB access logs" below.

Security groups follow least privilege: instances accept HTTP **only** from the
ALB security group — no direct internet access to the instances.

## What gets provisioned

| Module             | Resources |
|--------------------|-----------|
| `modules/vpc`      | VPC, 2 public + 2 private subnets across 2 AZs, internet gateway, NAT gateway, route tables |
| `modules/security-groups` | ALB security group (80/443), instance security group (HTTP from ALB only) |
| `modules/compute`  | ALB + listener + target group, launch template (Amazon Linux 2023, nginx via user data), Auto Scaling group, CloudWatch CPU alarm + SNS alert topic (toggleable) |

## Skills demonstrated

- **Infrastructure as Code** — Terraform ≥ 1.5, AWS provider v5, reusable modules with typed variables and outputs
- **AWS networking** — VPC design, subnetting with `cidrsubnet`, IGW/NAT, route tables
- **Compute & scaling** — launch templates, Auto Scaling groups, ALB health checks
- **Security** — least-privilege security groups, no hardcoded secrets
- **CI/CD** — GitHub Actions pipeline running `fmt`, `init`, and `validate` on every push/PR
- **Observability** — CloudWatch alarm on ASG average CPU with SNS notifications (optional email subscription, disable via `enable_cpu_alarm = false`)
- **State management** — opt-in S3 + DynamoDB remote-state backend shipped as an example

## Usage

```bash
# 1. Configure AWS credentials (env vars, SSO, or shared config)
export AWS_PROFILE=my-profile

# 2. Initialise and review the plan
terraform init
terraform plan -var="environment=dev"

# 3. Apply (creates real AWS resources - see the cost estimate below)
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

## ALB access logs

Access logging is off by default. For request-level logs (debugging 5xxs,
traffic auditing, Athena queries), `modules/compute/main.tf` contains a
commented, copy-paste-ready example: a log bucket with the ELB write policy
plus the `access_logs` block for the ALB. Uncomment and adapt it; logs land
under `s3://<bucket>/alb/AWSLogs/<account-id>/...` after about 5 minutes,
and a lifecycle rule expiring objects after 90 days keeps the storage
bill from growing forever.

## WAFv2 protection

The ALB is internet-facing with no WAF by default. For layer-7 defense
(SQL injection, cross-site scripting, request floods),
`modules/compute/main.tf` contains a commented, copy-paste-ready example:
an `aws_wafv2_web_acl` with the AWS Managed Common Rule Set and a
2,000-requests-per-5-minutes per-IP rate limit, plus the
`aws_wafv2_web_acl_association` that binds it to the ALB. Uncomment and
adapt it; deploy new managed rules in count mode first so you can inspect
sampled requests for false positives before blocks start dropping
legitimate traffic. Expect roughly $5/month per web ACL plus about $1
per million requests, with the managed rule group adding roughly $1 more
per million.

## Project structure

```
├── main.tf                  # provider + module composition
├── backend.tf.example       # optional S3 + DynamoDB remote state (copy to backend.tf)
├── variables.tf             # root inputs (region, env, CIDR, AZs, ASG sizing, ALB deletion protection, CPU alarm)
├── outputs.tf               # vpc_id, alb_dns_name, application_url
├── versions.tf              # Terraform + provider pins
├── modules/
│   ├── vpc/                 # VPC, subnets, IGW, NAT, route tables
│   ├── security-groups/     # ALB + instance security groups
│   └── compute/             # ALB, target group, launch template, ASG
├── .github/workflows/       # Terraform CI (fmt / init / validate)
└── terraform.tfvars.example
```

## Monthly cost estimate

Steady-state cost for the default configuration (`us-east-1`, On-Demand,
730-hour month, demo-level traffic). Unit rates checked against AWS pricing
in October 2026:

| Resource                          | Unit rate                    | Qty | Monthly      |
|-----------------------------------|------------------------------|-----|--------------|
| EC2 `t3.micro` (ASG, desired = 2)  | $0.0104/hr                   | 2   | ~$15.19      |
| Application Load Balancer         | $0.0225/hr + $0.008/LCU-hr   | 1   | ~$16.43 + LCU|
| NAT gateway (hourly)              | $0.045/hr                    | 1   | ~$32.85      |
| NAT gateway public IPv4           | $0.005/hr                    | 1   | ~$3.65       |
| NAT data processing               | $0.045/GB                    | ~0  | ~$0          |
| CloudWatch CPU alarm              | free (first 10 alarms)       | 1   | $0           |
| SNS topic + email alerts          | free tier (1,000 msgs/month) | 1   | $0           |
| VPC, subnets, IGW, route tables, security groups | free       | -   | $0           |
| **Total**                         |                              |     | **~$68.12**  |

Notes:

- The ALB's LCU line is negligible at demo traffic (one LCU covers 25 new
  connections/sec, 3,000 active connections/min, and 1 GB processed per
  hour). It becomes the line to watch under real load.
- The NAT gateway is the surprise cost in this config: nothing runs in the
  private subnets yet (instances launch in public subnets), so its $36.50
  fixed charge buys idle plumbing. For a short-lived demo, set
  `enable_nat_gateway = false` in the VPC module call to drop the total to
  about $31.62/month.
- Auto Scaling moves the EC2 line: desired capacity is 2 by default and can
  grow to 3 (`asg_max_size`), which adds one more $7.59 instance while
  scaled out.
- New AWS accounts get 12 months of free tier (750 ALB hours and 750 EC2
  micro hours per month), which can zero out most of this table for a year.
- Data transfer out to the internet is $0.09/GB after the account's
  100 GB/month free allowance. Small here, but the line to model for a real
  deployment.
- Always run `terraform destroy` when finished. ALB deletion protection
  defaults to `true`, so disable it first (see Usage step 5).

## FAQ

**Where is the Terraform state stored?**
Locally, in `terraform.tfstate`, by default. That is fine for a solo demo.
For anything shared, copy [`backend.tf.example`](backend.tf.example) to
`backend.tf` to move state to S3 with DynamoDB locking; see "Remote state"
above. `backend.tf` and `terraform.tfstate` are both gitignored — state
must never be committed.

**How do I pass AWS credentials?**
Through the AWS SDK chain Terraform inherits: `AWS_PROFILE` env var,
SSO (`aws sso login`), or a shared credentials file. Never put access keys
in `terraform.tfvars`, variables, or anywhere in the repo — `terraform.tfvars`
is gitignored for a reason.

**How do I tear everything down?**
ALB deletion protection defaults to `true` for prod-like safety, and it
blocks `terraform destroy`. Turn it off first, then destroy (see Usage step 5):

```bash
terraform apply -var="alb_deletion_protection=false"
terraform destroy
```

**Can I deploy to a different region?**
Yes: `-var="region=eu-west-1"` (or set `region` in `terraform.tfvars`).
The default AZs are `us-east-1a/b`, so override `azs` with two AZs in the
target region. Pricing in the cost table is `us-east-1` On-Demand and will
differ slightly elsewhere.

**How much does the default config cost?**
About $68/month steady-state, most of it the NAT gateway and ALB idle
charges (see the cost table). New accounts get 12 months of free tier that
can zero out the ALB and EC2 lines. For a short-lived demo, set
`enable_nat_gateway = false` to cut the total roughly in half.

**Do I need the S3 backend to get started?**
No. Run `terraform init` and `terraform plan` with local state first; add
the remote backend once you have a team or CI applying changes.

**Why are the private subnets empty?**
They are reserved for the planned RDS module — the NAT gateway exists so
that future database subnet has outbound internet (e.g., for patching)
without being directly reachable. Until then the ASG runs in the public
subnets.

## Roadmap

- [ ] Remote state backend (S3 + DynamoDB) enabled
- [ ] HTTPS listener with ACM certificate
- [ ] RDS module in private subnets
- [ ] `tflint` and `checkov` in CI
