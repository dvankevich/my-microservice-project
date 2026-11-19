# Lesson 5: Terraform AWS Infrastructure (S3 Backend, VPC, ECR, EKS)

This directory contains Terraform configurations to provision foundational AWS infrastructure in `eu-central-1` for a microservice project: remote state storage, a multi-AZ Virtual Private Cloud (VPC), a private container image registry (ECR), and an Amazon EKS cluster.

## Project Structure

```text
lesson-5/
├── backend.tf                 # S3 remote state backend configuration (native S3 lockfile)
├── main.tf                    # Root module wiring s3_backend, vpc, ecr, and eks modules
├── outputs.tf                 # Root outputs
├── .terraform.lock.hcl        # Provider dependency lock file
└── modules/
    ├── ecr/
    │   ├── ecr.tf
    │   ├── outputs.tf
    │   └── variables.tf
    ├── eks/
    │   ├── eks.tf             # EKS cluster, cluster IAM role, and access configuration
    │   ├── node.tf            # Managed node group and node IAM role
    │   ├── outputs.tf
    │   └── variables.tf
    ├── s3-backend/
    │   ├── outputs.tf         # Outputs S3 bucket name
    │   ├── s3.tf              # S3 state bucket, versioning, and ownership controls
    │   └── variables.tf       # Bucket name variable
    └── vpc/
        ├── outputs.tf
        ├── routes.tf
        ├── variables.tf
        └── vpc.tf
```

## Modules Overview

### `s3-backend` (`./modules/s3-backend`)

Provisions remote state storage in AWS using the native S3 backend locking:

* **S3 Bucket (`s3.tf`)**: Creates the state bucket (`tfstate-bucket-lesson5`), enables **Versioning** to preserve state history, and enforces `BucketOwnerEnforced` object ownership.
* **State Locking**: Locking is handled natively by the S3 backend via `use_lockfile = true` in `backend.tf`. No separate DynamoDB table is required or provisioned.
```

### `vpc` (`./modules/vpc`)

Provisions core networking in `eu-central-1` (`10.0.0.0/16` by default in `main.tf`) across three availability zones (`eu-central-1a`, `eu-central-1b`, `eu-central-1c`):

* **VPC, Subnets & NAT Gateway (`vpc.tf`)**: Creates a VPC with DNS support and DNS hostnames enabled, three public subnets (`10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`) with `map_public_ip_on_launch = true`, three private subnets (`10.0.4.0/24`, `10.0.5.0/24`, `10.0.6.0/24`), an Internet Gateway (`igw`), and a single shared NAT Gateway (`nat`) with an Elastic IP (`aws_eip.nat`) placed in the first public subnet (`public[0]`) to keep test environment costs down.
* **Routing (`routes.tf`)**: Creates a public route table with a `0.0.0.0/0` route pointing to the Internet Gateway associated with all public subnets, and a shared private route table with a `0.0.0.0/0` route pointing to the NAT Gateway associated with all private subnets.

### `ecr` (`./modules/ecr`)

Provisions a private Amazon ECR repository intended for container images shared across compute workloads such as ECS and EKS:

* **Repository (`ecr.tf`)**: Creates an `aws_ecr_repository` (default name `lesson-5-ecr`) with `MUTABLE` image tags, `force_delete = true` (allowing deletion even when images are present), and `scan_on_push = true` enabled for vulnerability scanning.
* **Repository Policy (`ecr.tf`)**: Attaches an `aws_ecr_repository_policy` scoped to the current AWS account (`data.aws_caller_identity.current`) to allow image push and pull operations for account principals and workloads.

### `eks` (`./modules/eks`)

Provisions a managed Amazon EKS cluster in `eu-central-1` that runs on the public subnets created by the `vpc` module. The cluster is intended as a lightweight development/test environment for containerized workloads that pull images from the ECR repository.

* **Cluster & IAM Role (`eks.tf`)**: Creates an IAM role for the EKS control plane with the `AmazonEKSClusterPolicy` attached, then creates the `aws_eks_cluster` resource (default name `eks-cluster-demo`). The cluster is configured with both public and private API endpoint access and uses `authentication_mode = "API"` together with `bootstrap_cluster_creator_admin_permissions = true` so the identity that creates the cluster receives administrator access.
* **Managed Node Group (`node.tf`)**: Creates a managed node group (`general`) that runs on the public subnets. The node group uses a Free Tier–eligible instance type (recommended: `t3.micro`), with a small scaling configuration (`desired_size = 1`, `min_size = 1`, `max_size = 2`) to keep costs low. The node IAM role is attached with the standard worker policies (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryReadOnly`).

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