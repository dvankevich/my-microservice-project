# Lesson 7: Terraform AWS Infrastructure (S3 Backend, VPC, ECR, EKS) & Helm Deployment

This directory contains Terraform configurations to provision foundational AWS infrastructure in `eu-central-1` (remote state storage, multi-AZ VPC, private ECR registry, and an Amazon EKS cluster) along with a custom Helm chart to deploy the Django/Wagtail application and PostgreSQL database.

## Project Structure

```text
lesson-7/
├── .gitignore                 # Ignores Terraform state/cache and local Helm secrets.yaml
├── backend.tf                 # S3 remote state backend configuration (native S3 lockfile)
├── main.tf                    # Root module wiring s3_backend, vpc, ecr, and eks modules
├── outputs.tf                 # Root outputs
├── .terraform.lock.hcl        # Provider dependency lock file
├── modules/
│   ├── ecr/
│   │   ├── ecr.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── eks/
│   │   ├── eks.tf             # EKS cluster, cluster IAM role, and access configuration
│   │   ├── node.tf            # Managed node group and node IAM role
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── s3-backend/
│   │   ├── outputs.tf         # Outputs S3 bucket name
│   │   ├── s3.tf              # S3 state bucket, versioning, and ownership controls
│   │   └── variables.tf       # Bucket name variable
│   └── vpc/
│       ├── outputs.tf
│       ├── routes.tf
│       ├── variables.tf
│       └── vpc.tf
└── charts/
    └── django-app/
        ├── Chart.yaml
        ├── values.yaml            # Public application configuration (ConfigMap values, resources, HPA)
        ├── secrets.yaml.example   # Template for sensitive credentials (committed to Git)
        └── templates/
            ├── configmap.yaml     # Non-sensitive environment variables
            ├── secret.yaml        # Kubernetes Secret for SECRET_KEY and POSTGRES_PASSWORD
            ├── deployment.yaml    # Django/Wagtail Deployment with PostgreSQL readiness initContainer
            ├── postgres.yaml      # PostgreSQL 16 Deployment and ClusterIP Service
            ├── service.yaml       # AWS LoadBalancer Service exposing port 80 -> 8000
            └── hpa.yaml           # HorizontalPodAutoscaler based on CPU utilization

```

## Modules Overview

### `s3-backend` (`./modules/s3-backend`)

Provisions remote state storage in AWS using the native S3 backend locking:

* **S3 Bucket (`s3.tf`)**: Creates the state bucket (`tfstate-bucket-lesson5`), enables **Versioning** to preserve state history, and enforces `BucketOwnerEnforced` object ownership.
* **State Locking**: Locking is handled natively by the S3 backend via `use_lockfile = true` in `backend.tf`. No separate DynamoDB table is required or provisioned.

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
* **Managed Node Group (`node.tf`)**: Creates a managed node group (`general`) running on the public subnets using `t3.small` instances (`desired_size = 1`, `min_size = 1`, `max_size = 2`).
* **Why `t3.small` instead of `t3.micro`:** In AWS EKS, the VPC CNI plugin restricts `t3.micro` instances to a maximum of **4 pods per node** due to ENI IP address limits. Because system add-ons (`coredns`) already occupy 2 pod slots, a single `t3.micro` node triggers `0/1 nodes are available: 1 Too many pods` scheduling errors and leaves insufficient RAM (1 GiB total) to run both the Django application and PostgreSQL alongside HPA scaling. Switching to `t3.small` provides **2 GiB of RAM** and raises the pod density limit to **11 pods per node**, allowing all system and application workloads to run on a single cost-effective node.
* **IAM Permissions:** The node IAM role is attached with the standard worker policies (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryReadOnly`).

## Usage

Run commands from the `lesson-7` directory with valid AWS credentials configured for `eu-central-1`:

```bash
cd lesson-7

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

## Build and Push Django Docker Image to ECR

After provisioning the infrastructure, build the Django application image and push it to the newly created ECR repository.

### 1. Export ECR Repository Variables

Retrieve the repository URI from Terraform outputs (using `-raw` to omit quotes) and extract the registry URL and repository name:

```bash
export AWS_REGION="eu-central-1"
export ECR_REPO_URL=$(terraform output -raw repository_url)
export ECR_REGISTRY="${ECR_REPO_URL%/*}"
export ECR_REPO_NAME="${ECR_REPO_URL#*/}"

```

### 2. Authenticate Docker with Amazon ECR

Log in to your private ECR registry:

```bash
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

```

### 3. Build the Docker Image

Navigate to the Django project directory (`lesson-4/mysite`) and build the image targeting `linux/amd64` (compatible with EKS worker nodes):

```bash
cd ../lesson-4/mysite
docker build --platform linux/amd64 -t "$ECR_REPO_URL:latest" .

```

### 4. Push the Image to ECR

Upload the tagged image to the repository:

```bash
docker push "$ECR_REPO_URL:latest"

```

### 5. Verify the Uploaded Image

Confirm that the `latest` tag is available in Amazon ECR and return to `lesson-7`:

```bash
aws ecr list-images --repository-name "$ECR_REPO_NAME" --region "$AWS_REGION"
cd ../../lesson-7

```

## Deploy Django Application to EKS with Helm

The `charts/django-app` Helm chart separates non-sensitive configuration (`ConfigMap` via `values.yaml`) from sensitive credentials (`Kubernetes Secret` via `secrets.yaml`).

### 1. Configure `kubectl` for EKS

Update your local kubeconfig to connect to the `eks-cluster-demo` cluster:

```bash
aws eks update-kubeconfig --region "$AWS_REGION" --name eks-cluster-demo
kubectl get nodes

```

### 2. Prepare Local Secrets File

Copy the example secrets template and populate your actual `SECRET_KEY` and `POSTGRES_PASSWORD`. The `charts/**/secrets.yaml` file is excluded via `.gitignore` so credentials are never committed to version control:

```bash
cp charts/django-app/secrets.yaml.example charts/django-app/secrets.yaml
# Edit charts/django-app/secrets.yaml with your actual credentials

```

### 3. Validate and Install the Helm Chart

Lint the chart and deploy the release into the `wagtail` namespace, passing both `values.yaml` and your local `secrets.yaml`:

```bash
helm lint ./charts/django-app

helm upgrade --install django-app ./charts/django-app \
  -n wagtail \
  --create-namespace \
  -f ./charts/django-app/values.yaml \
  -f ./charts/django-app/secrets.yaml

```

### 4. Verify the Deployment

Check that both `postgres` and `django` pods are `Running`, the `Secret` is created, and retrieve the AWS LoadBalancer DNS name (`EXTERNAL-IP`):

```bash
kubectl get pods,svc,hpa,secret -n wagtail

```

Once the ELB finishes provisioning (1–2 minutes), verify HTTP access:

```bash
curl -I http://<EXTERNAL-IP>

```

### 5. Create Django/Wagtail Superuser

Once both `postgres` and `django` pods reach the `1/1 Running` state (ensuring database migrations in `entrypoint.sh` have completed), create an administrative user non-interactively via environment variables:

```bash
kubectl exec deployment/django-app-django -n wagtail -- \
  env DJANGO_SUPERUSER_USERNAME=admin \
      DJANGO_SUPERUSER_EMAIL=admin@example.com \
      DJANGO_SUPERUSER_PASSWORD=your_password \
  python manage.py createsuperuser --noinput

```

*(Alternatively, run `kubectl exec -it deployment/django-app-django -n wagtail -- python manage.py createsuperuser` for interactive prompts.)*

Afterward, sign in to the Wagtail admin interface at `http://<EXTERNAL-IP>/admin/`.

> **Note:** Because `postgres.yaml` uses ephemeral `emptyDir` storage for lightweight testing, recreating or rescheduling the PostgreSQL pod will reset the database and require re-running this command.

## Cleanup

First uninstall the Helm release so Kubernetes deletes the AWS Classic Load Balancer and releases its network interfaces, then tear down all Terraform-managed resources:

```bash
helm uninstall django-app -n wagtail
terraform destroy

```
