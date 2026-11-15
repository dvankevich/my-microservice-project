# Lesson 5: Terraform AWS Infrastructure (S3 Backend, VPC, ECR)

This directory contains Terraform configurations to provision foundational AWS infrastructure in `eu-central-1` for a microservice project: remote state storage, a multi-AZ Virtual Private Cloud (VPC), and a private container image registry (ECR).

## Project Structure

```text
lesson-5/
├── backend.tf                 # S3 remote state backend configuration (native S3 lockfile)
├── main.tf                    # Root module wiring s3_backend, vpc, and ecr modules
├── outputs.tf                 # Root outputs (s3_bucket_name, repository_url)
├── .terraform.lock.hcl        # Provider dependency lock file (hashicorp/aws v6.73.0)
└── modules/
    ├── ecr/
    │   ├── ecr.tf             # Private ECR repository resource
    │   ├── outputs.tf         # Outputs repository_url
    │   └── variables.tf       # ECR repository name variable
    ├── s3-backend/
    │   ├── dynamodb.tf        # Commented out (DynamoDB lock table no longer used for state locking)
    │   ├── outputs.tf         # Outputs S3 bucket name
    │   ├── s3.tf              # S3 state bucket, versioning, and ownership controls
    │   └── variables.tf       # Bucket and DynamoDB table name variables
    └── vpc/
        ├── outputs.tf         # Outputs VPC ID, public/private subnet IDs, and IGW ID
        ├── routes.tf          # Public route table, default internet route, and associations
        ├── variables.tf       # CIDR blocks, AZs, and VPC name variables
        └── vpc.tf             # VPC, public/private subnets, and Internet Gateway

```

## Modules Overview

### `s3-backend` (`./modules/s3-backend`)

Provisions remote state storage resources in AWS:

* **S3 Bucket (`s3.tf`)**: Creates the state bucket (`tfstate-bucket-lesson5`), enables **Versioning** to preserve state history, and enforces `BucketOwnerEnforced` object ownership.
* **DynamoDB State Locking (`dynamodb.tf`)**: All resource definitions in `dynamodb.tf` are commented out because state locking is handled natively by the S3 backend via `use_lockfile = true` in `backend.tf` instead of a DynamoDB lock table. Using S3 lockfiles removes the need to provision and maintain a separate DynamoDB table for state locking while keeping concurrent run protection in place. (Note: `table_name` in `modules/s3-backend/variables.tf` and `main.tf` can also be cleaned up or left unused until refactored.)

### `vpc` (`./modules/vpc`)

Provisions core networking in `eu-central-1` (`10.0.0.0/16` by default in `main.tf`) across three availability zones (`eu-central-1a`, `eu-central-1b`, `eu-central-1c`):

* **VPC & Subnets (`vpc.tf`)**: Creates a VPC with DNS support and DNS hostnames enabled, three public subnets (`10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`) with `map_public_ip_on_launch = true`, three private subnets (`10.0.4.0/24`, `10.0.5.0/24`, `10.0.6.0/24`), and an Internet Gateway (`igw`).
* **Routing (`routes.tf`)**: Creates a public route table with a `0.0.0.0/0` route pointing to the Internet Gateway and associates it with all public subnets.

### `ecr` (`./modules/ecr`)

Provisions a private Amazon ECR repository intended for container images shared across compute workloads such as ECS and EKS:

* **Repository (`ecr.tf`)**: Creates an `aws_ecr_repository` (default name `lesson-5-ecr`) with `MUTABLE` image tags, `force_delete = true` (allowing deletion even when images are present), and `scan_on_push = true` enabled for vulnerability scanning.

## Usage

Run commands from the `lesson-5` directory with valid AWS credentials configured for `eu-central-1`:

```bash
cd lesson-5

```

### Initialize

Download providers, initialize modules, and configure the remote state backend:

```bash
terraform init

```

### Plan

Preview the execution plan and verify which resources will be created, changed, or destroyed:

```bash
terraform plan

```

### Apply

Provision or update the infrastructure in AWS:

```bash
terraform apply

```

### Destroy

Tear down all Terraform-managed resources in this configuration:

```bash
terraform destroy

```