# Lesson 7: Terraform AWS Infrastructure (S3 Backend, VPC, ECR, EKS) & Helm Deployment

This directory contains Terraform configurations to provision foundational AWS infrastructure in `eu-central-1` (remote state storage, multi-AZ VPC, private ECR registry, and an Amazon EKS cluster) along with a custom Helm chart to deploy the Django/Wagtail application, PostgreSQL database backed by persistent AWS EBS storage, HTTPS access via `ingress-nginx` and `cert-manager`, and horizontal pod autoscaling via HPA.

## Project Structure

```text
lesson-7/
├── .gitignore                 # Ignores Terraform state/cache and local Helm secrets.yaml
├── README.md                  # Infrastructure and deployment documentation
├── LOAD_TESTING.md            # Load testing guide and HPA scaling verification scenarios
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
│   │   ├── ebs-csi.tf         # OIDC provider, IAM role, and AWS EBS CSI driver add-on
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
        ├── values.yaml            # Public application configuration (ConfigMap values, Ingress, persistence, HPA)
        ├── secrets.yaml.example   # Template for sensitive credentials (committed to Git)
        └── templates/
            ├── configmap.yaml     # Non-sensitive environment variables (including CSRF_TRUSTED_ORIGINS)
            ├── secret.yaml        # Kubernetes Secret for SECRET_KEY and POSTGRES_PASSWORD
            ├── deployment.yaml    # Django/Wagtail Deployment with PostgreSQL readiness initContainer
            ├── postgres.yaml      # PostgreSQL 16 Deployment (Recreate strategy) and ClusterIP Service
            ├── pvc.yaml           # PersistentVolumeClaim (5Gi) for PostgreSQL data
            ├── storageclass.yaml  # Encrypted gp3 StorageClass (ebs.csi.aws.com, WaitForFirstConsumer)
            ├── service.yaml       # ClusterIP Service exposing port 80 -> 8000 to Ingress
            ├── ingress.yaml       # NGINX Ingress resource with cert-manager TLS annotations
            └── hpa.yaml           # HorizontalPodAutoscaler (2–6 replicas at >70% CPU utilization)
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
* **Managed Node Group (`node.tf`)**: Creates a managed node group (`general`) running on the public subnets using `t3.small` instances (`desired_size = 2`, `min_size = 2`, `max_size = 3`).
  * **Why `t3.small` (2 nodes) instead of `t3.micro` (1 node):** In AWS EKS, the VPC CNI plugin restricts `t3.micro` instances to a maximum of **4 pods per node** due to ENI IP address limits. Switching to `t3.small` provides **2 GiB of RAM** and raises the pod density limit to **11 pods per node**. Running 2 `t3.small` nodes provides enough pod slots and memory for system add-ons (`coredns`, `aws-node`, `kube-proxy`, `ebs-csi`), `ingress-nginx`, `cert-manager`, `metrics-server`, PostgreSQL, and horizontally scaled Django pods without `Too many pods` scheduling errors.
  * **Autoscaler Lifecycle Rule:** `node.tf` includes `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` to prevent Terraform from conflicting with cluster autoscalers. If modifying `desired_size` on an existing cluster, update it via AWS CLI (`aws eks update-nodegroup-config`).
* **EBS CSI Driver & IRSA (`ebs-csi.tf`)**: Provisions an IAM OIDC identity provider for the cluster, creates a dedicated IAM role with `AmazonEBSCSIDriverPolicy` bound to the `kube-system:ebs-csi-controller-sa` service account, and installs the `aws-ebs-csi-driver` EKS add-on so Kubernetes can dynamically provision and attach AWS EBS volumes for stateful workloads.
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

Before building the image, ensure `lesson-4/mysite/mysite/settings/docker.py` configures HTTPS proxy headers and reads `CSRF_TRUSTED_ORIGINS` from the environment so Django 6.1 allows `POST` requests (such as `/admin/login/`) behind `ingress-nginx`:

```python
csrf_origins = os.environ.get("CSRF_TRUSTED_ORIGINS", "")
CSRF_TRUSTED_ORIGINS = [
    origin.strip() for origin in csrf_origins.split(",") if origin.strip()
]
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
```

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

## Deploy Ingress, TLS (`cert-manager`), and Django Application to EKS

The `charts/django-app` Helm chart separates non-sensitive configuration (`ConfigMap` via `values.yaml`) from sensitive credentials (`Kubernetes Secret` via `secrets.yaml`), provisions an encrypted `gp3` AWS EBS volume via `PersistentVolumeClaim` (`subPath: pgdata`, `Recreate` deployment strategy), and exposes the application over HTTPS via `ingress-nginx` and Let's Encrypt.

### 1. Configure `kubectl` for EKS

Update your local kubeconfig to connect to the `eks-cluster-demo` cluster and verify both nodes are `Ready`:

```bash
aws eks update-kubeconfig --region "$AWS_REGION" --name eks-cluster-demo
kubectl get nodes
```

### 2. Install `ingress-nginx` and Configure DNS

Install the NGINX Ingress Controller, which provisions a single AWS LoadBalancer for external HTTP/HTTPS traffic:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace
```

Retrieve the `EXTERNAL-IP` (ELB DNS hostname) of `ingress-nginx-controller`:

```bash
kubectl get svc -n ingress-nginx
```

Configure DNS for your domain (`django-app.dvankevich.pp.ua`):

* **Recommended (`CNAME` record):** Point `django-app` to the `EXTERNAL-IP` ELB hostname (`<id>.eu-central-1.elb.amazonaws.com`).
* **Alternative (`A` record):** Resolve the ELB's current IPv4 addresses with `dig +short <EXTERNAL-IP>` and add them as `A` records.

Verify DNS propagation before issuing certificates:

```bash
dig +short django-app.dvankevich.pp.ua
```

### 3. Install `cert-manager` and Create Let's Encrypt `ClusterIssuer`

Install `cert-manager` with CRDs enabled:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

Once the `cert-manager` pods are `Running`, create the production ACME `ClusterIssuer`:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@dvankevich.pp.ua
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

### 4. Prepare Local Secrets File

Copy the example secrets template and populate your actual `SECRET_KEY` and `POSTGRES_PASSWORD`. The `charts/**/secrets.yaml` file is excluded via `.gitignore` so credentials are never committed to version control:

```bash
cp charts/django-app/secrets.yaml.example charts/django-app/secrets.yaml
# Edit charts/django-app/secrets.yaml with your actual credentials
```

### 5. Validate and Install the Helm Chart

Lint the chart and deploy the release into the `wagtail` namespace, passing both `values.yaml` and your local `secrets.yaml`:

```bash
helm lint ./charts/django-app

helm upgrade --install django-app ./charts/django-app \
  -n wagtail \
  --create-namespace \
  -f ./charts/django-app/values.yaml \
  -f ./charts/django-app/secrets.yaml
```

*(If updating an existing deployment after pushing a new image with the `:latest` tag, run `kubectl rollout restart deployment/django-app-django -n wagtail` to pull the updated image.)*

### 6. Verify the Deployment and TLS Certificate

Check that the `PersistentVolumeClaim` is `Bound`, all pods are `Running`, and the TLS `Certificate` reaches `READY: True` (takes ~1–2 minutes for the Let's Encrypt HTTP-01 challenge):

```bash
kubectl get pvc,pv,pods,svc,ingress,certificate,hpa,secret -n wagtail
```

Verify HTTPS access:

```bash
curl -I https://django-app.dvankevich.pp.ua
```

### 7. Create Django/Wagtail Superuser

Once both `postgres` and `django` pods reach the `1/1 Running` state (ensuring database migrations in `entrypoint.sh` have completed), create an administrative user non-interactively via environment variables:

```bash
kubectl exec deployment/django-app-django -n wagtail -- \
  env DJANGO_SUPERUSER_USERNAME=admin \
      DJANGO_SUPERUSER_EMAIL=admin@example.com \
      DJANGO_SUPERUSER_PASSWORD=your_password \
  python manage.py createsuperuser --noinput
```

*(Alternatively, run `kubectl exec -it deployment/django-app-django -n wagtail -- python manage.py createsuperuser` for interactive prompts.)*

Afterward, sign in to the Wagtail admin interface at `https://django-app.dvankevich.pp.ua/admin/`.

> **Note:** Because PostgreSQL stores its data on an AWS EBS volume via `PersistentVolumeClaim` (`django-app-postgres-pvc`), database tables and the superuser account persist across pod restarts and redeployments. If the PostgreSQL volume is ever recreated from scratch while the Django pod is already running, trigger `kubectl rollout restart deployment/django-app-django -n wagtail` so `entrypoint.sh` re-runs `python manage.py migrate`.

## Horizontal Pod Autoscaler (HPA) Configuration

Amazon EKS does not include `metrics-server` by default. Without it, `HorizontalPodAutoscaler` reports `cpu: <unknown>/70%` and cannot scale workloads.

### 1. Install `metrics-server`

Install `metrics-server` into the `kube-system` namespace:

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system \
  --set 'args[0]=--kubelet-insecure-tls'
```

Verify that node and pod resource metrics are available (takes ~30–60 seconds):

```bash
kubectl top nodes
kubectl top pods -n wagtail
```

### 2. Configure HPA Parameters in `values.yaml`

The Helm chart (`templates/hpa.yaml` using `autoscaling/v2`) scales `django-app-django` based on CPU utilization relative to the pod's `100m` CPU request:

```yaml
replicaCount: 2

resources:
  requests:
    cpu: 100m
    memory: 200Mi
  limits:
    cpu: 400m
    memory: 400Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 6
  targetCPUUtilizationPercentage: 70
```

Apply the configuration and verify that HPA reads live CPU utilization (`cpu: 1%/70%`) and maintains between `2` and `6` replicas:

```bash
helm upgrade --install django-app ./charts/django-app \
  -n wagtail \
  -f ./charts/django-app/values.yaml \
  -f ./charts/django-app/secrets.yaml

kubectl get hpa,pods -n wagtail
```

> **Load Testing:** For instructions and examples on generating synthetic CPU/HTTP load to verify automatic scaling from `2` to `6` pods, see [`LOAD_TESTING.md`](./LOAD_TESTING.md).

## Cleanup

Uninstall all Helm releases first so Kubernetes deletes the AWS Classic Load Balancer (`ingress-nginx`), delete the `PersistentVolumeClaim` so AWS deletes the underlying EBS volume, and finally tear down all Terraform-managed resources:

```bash
helm uninstall django-app -n wagtail
kubectl delete pvc django-app-postgres-pvc -n wagtail
helm uninstall cert-manager -n cert-manager
helm uninstall ingress-nginx -n ingress-nginx
helm uninstall metrics-server -n kube-system
terraform destroy
```