# Lesson 7: Terraform AWS Infrastructure (S3 Backend, VPC, ECR, EKS) & Helm Deployment

This directory contains Terraform configurations to provision foundational AWS infrastructure in `eu-central-1` (remote state storage, multi-AZ VPC, private ECR registry, and an Amazon EKS cluster), cluster add-ons (`ingress-nginx` with Multi-AZ High Availability and `cert-manager` with Let's Encrypt `ClusterIssuer`), a declarative Jenkins CI/CD server using Kaniko and IRSA, and a custom Helm chart to deploy the Django/Wagtail application with PostgreSQL on persistent AWS EBS storage, dual L4 `LoadBalancer` / L7 HTTPS `Ingress` access, horizontal pod autoscaling (HPA), and `topologySpreadConstraints`.

## Project Structure

```text
lesson-7/
├── .gitignore                 # Ignores Terraform state/cache and local secrets.yaml files
├── README.md                  # Infrastructure, deployment, and CI/CD documentation
├── LOAD_TESTING.md            # Load testing guide and HPA scaling verification scenarios
├── AUTOMATED_TESTING.md       # Documentation for the automated infrastructure test script
├── run-tests.sh               # Automated TLS, HA, rolling update, and load testing script
├── backend.tf                 # S3 remote state backend configuration (native S3 lockfile)
├── main.tf                    # Root module wiring s3_backend, vpc, ecr, eks, cluster_addons, and jenkins
├── outputs.tf                 # Root outputs (S3, VPC, ECR, EKS, Ingress ELB hostname, and Jenkins info)
├── .terraform.lock.hcl        # Provider dependency lock file
├── modules/
│   ├── cluster-addons/
│   │   ├── main.tf            # Multi-AZ ingress-nginx, cert-manager, and letsencrypt-prod ClusterIssuer
│   │   ├── outputs.tf         # Exports ingress_elb_hostname and cluster_issuer_name
│   │   ├── variables.tf       # Ingress replica count, ACME email, and ClusterIssuer variables
│   │   └── versions.tf        # Required Helm and Kubernetes provider version constraints
│   ├── ecr/
│   │   ├── ecr.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── eks/
│   │   ├── ebs-csi.tf         # OIDC provider, IAM role, and AWS EBS CSI driver add-on
│   │   ├── eks.tf             # EKS cluster, cluster IAM role, and access configuration
│   │   ├── node.tf            # Managed node group and node IAM role
│   │   ├── outputs.tf         # Exports cluster endpoint, name, node role ARN, and OIDC provider outputs
│   │   └── variables.tf
│   ├── jenkins/
│   │   ├── jenkins.tf         # IAM role (IRSA), Kubernetes Namespace/SA, and Jenkins Helm release
│   │   ├── outputs.tf         # Outputs release name, namespace, and HTTPS URL
│   │   ├── values.yaml        # Jenkins controller, plugins, Ingress, persistence, and JCasC seed-job
│   │   ├── secrets.yaml.example # Template for Jenkins admin password and GitHub PAT (committed to Git)
│   │   ├── secrets.yaml       # Local sensitive JCasC credentials and admin password (gitignored)
│   │   ├── variables.tf       # Module input variables (including OIDC and dynamic ECR repository URL)
│   │   └── versions.tf        # Required Helm and Kubernetes provider version constraints
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
        ├── values.yaml            # Public application configuration (LoadBalancer/ClusterIP switch, Ingress, persistence, HPA)
        ├── secrets.yaml.example   # Template for sensitive credentials (committed to Git)
        └── templates/
            ├── configmap.yaml     # Non-sensitive environment variables (including CSRF_TRUSTED_ORIGINS)
            ├── secret.yaml        # Kubernetes Secret for SECRET_KEY and POSTGRES_PASSWORD
            ├── deployment.yaml    # Django/Wagtail Deployment with PostgreSQL readiness initContainer and topologySpreadConstraints
            ├── postgres.yaml      # PostgreSQL 16 Deployment (Recreate strategy) and ClusterIP Service
            ├── pvc.yaml           # PersistentVolumeClaim (5Gi) for PostgreSQL data
            ├── storageclass.yaml  # Encrypted gp3 StorageClass (ebs.csi.aws.com, WaitForFirstConsumer)
            ├── service.yaml       # Configurable Service (LoadBalancer by default, switchable to ClusterIP)
            ├── ingress.yaml       # NGINX Ingress resource with cert-manager TLS annotations
            └── hpa.yaml           # HorizontalPodAutoscaler (2–6 replicas at >70% CPU utilization)
```

*(Note: The declarative CI pipeline definition for building the Django Docker image resides in the application directory at `../lesson-4/mysite/Jenkinsfile`.)*

## Modules Overview

### `s3-backend` (`./modules/s3-backend`)

Provisions remote state storage in AWS using the native S3 backend locking:

- **S3 Bucket (`s3.tf`)**: Creates the state bucket (`tfstate-bucket-lesson5`), enables **Versioning** to preserve state history, and enforces `BucketOwnerEnforced` object ownership.
- **State Locking**: Locking is handled natively by the S3 backend via `use_lockfile = true` in `backend.tf`. No separate DynamoDB table is required or provisioned.

### `vpc` (`./modules/vpc`)

Provisions core networking in `eu-central-1` (`10.0.0.0/16` by default in `main.tf`) across three availability zones (`eu-central-1a`, `eu-central-1b`, `eu-central-1c`):

- **VPC, Subnets & NAT Gateway (`vpc.tf`)**: Creates a VPC with DNS support and DNS hostnames enabled, three public subnets (`10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`) with `map_public_ip_on_launch = true`, three private subnets (`10.0.4.0/24`, `10.0.5.0/24`, `10.0.6.0/24`), an Internet Gateway (`igw`), and a single shared NAT Gateway (`nat`) with an Elastic IP (`aws_eip.nat`) placed in the first public subnet (`public[0]`) to keep test environment costs down.
- **Routing (`routes.tf`)**: Creates a public route table with a `0.0.0.0/0` route pointing to the Internet Gateway associated with all public subnets, and a shared private route table with a `0.0.0.0/0` route pointing to the NAT Gateway associated with all private subnets.

### `ecr` (`./modules/ecr`)

Provisions a private Amazon ECR repository intended for container images shared across compute workloads such as ECS and EKS:

- **Repository (`ecr.tf`)**: Creates an `aws_ecr_repository` (default name `lesson-5-ecr`) with `MUTABLE` image tags, `force_delete = true` (allowing deletion even when images are present), and `scan_on_push = true` enabled for vulnerability scanning.
- **Repository Policy (`ecr.tf`)**: Attaches an `aws_ecr_repository_policy` scoped to the current AWS account (`data.aws_caller_identity.current`) to allow image push and pull operations for account principals and workloads.

### `eks` (`./modules/eks`)

Provisions a managed Amazon EKS cluster in `eu-central-1` that runs on the public subnets created by the `vpc` module.

- **Cluster & IAM Role (`eks.tf`)**: Creates an IAM role for the EKS control plane with the `AmazonEKSClusterPolicy` attached, then creates the `aws_eks_cluster` resource (default name `eks-cluster-demo`). The cluster is configured with both public and private API endpoint access and uses `authentication_mode = "API"` together with `bootstrap_cluster_creator_admin_permissions = true` so the identity that creates the cluster receives administrator access.
- **Managed Node Group (`node.tf`)**: Creates a managed node group (`general`) running on the public subnets using `t3.small` instances (`desired_size = 3`, `min_size = 2`, `max_size = 4`).
  - **Why `t3.small` (3 nodes) instead of `t3.micro`:** In AWS EKS, the VPC CNI plugin restricts `t3.micro` instances to a maximum of **4 pods per node** due to ENI IP address limits. Switching to `t3.small` provides **2 GiB of RAM** and raises the pod density limit to **11 pods per node**. Running 3 `t3.small` nodes (33 pod slots total) provides enough capacity for system add-ons (`coredns`, `aws-node`, `kube-proxy`, `ebs-csi`), Multi-AZ `ingress-nginx`, `cert-manager`, `metrics-server`, PostgreSQL, horizontally scaled Django pods, and the Jenkins controller with dynamic Kubernetes Kaniko agent pods without `Too many pods` scheduling errors.
  - **Autoscaler Lifecycle Rule:** `node.tf` includes `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` to prevent Terraform from conflicting with cluster autoscalers. If modifying `desired_size` on an existing cluster, update it via AWS CLI (`aws eks update-nodegroup-config`).
- **EBS CSI Driver & IRSA (`ebs-csi.tf` & `outputs.tf`)**: Provisions an IAM OIDC identity provider for the cluster, creates a dedicated IAM role with `AmazonEBSCSIDriverPolicy` bound to `kube-system:ebs-csi-controller-sa`, installs the `aws-ebs-csi-driver` EKS add-on, and exports `oidc_provider_arn` and `oidc_provider_url` so downstream modules (such as `jenkins`) can configure IRSA for their own service accounts.
- **IAM Permissions:** The node IAM role is attached with the standard worker policies (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryReadOnly`).

### `cluster-addons` (`./modules/cluster-addons`)

Provisions cluster-wide ingress and TLS certificate management via the Terraform `helm` and `kubernetes` providers:

- **Multi-AZ `ingress-nginx` (`main.tf`)**: Installs `ingress-nginx` with `replicaCount = 2` and `topologySpreadConstraints` keyed on `topology.kubernetes.io/zone` (`maxSkew = 1`, `whenUnsatisfiable = "ScheduleAnyway"`). Rather than deploying separate Ingress controllers per zone, running multiple replicas of a single controller spread across AWS Availability Zones eliminates single-node/single-AZ failure points while sharing a single AWS LoadBalancer.
- **`cert-manager` & `ClusterIssuer` (`main.tf`)**: Installs `cert-manager` (`crds.enabled = true`) and provisions the production Let's Encrypt `ClusterIssuer` (`letsencrypt-prod`) using HTTP-01 challenge validation via the `nginx` ingress class.
- **ELB Hostname Output (`outputs.tf`)**: Reads the provisioned `ingress-nginx-controller` `Service` and exports `ingress_elb_hostname` so DNS `CNAME` records for `django-app.dvankevich.pp.ua` and `jenkins.dvankevich.pp.ua` can be retrieved directly from Terraform outputs.

### `jenkins` (`./modules/jenkins`)

Deploys Jenkins into the `jenkins` namespace using the Terraform `helm` and `kubernetes` providers authenticated via short-lived EKS IAM tokens (`data.aws_eks_cluster_auth`):

- **IRSA for Kaniko ECR Builds (`jenkins.tf`)**: Creates an IAM role (`eks-cluster-demo-jenkins-kaniko-role`) with ECR push/pull permissions and binds it to the `jenkins-sa` Kubernetes `ServiceAccount` (`eks.amazonaws.com/role-arn`). Ephemeral Kaniko build pods assume this role automatically without static AWS keys or privileged Docker-in-Docker daemons.
- **Helm Release & Ingress (`jenkins.tf` & `values.yaml`)**: Installs the official `jenkinsci/jenkins` chart as a `ClusterIP` service and exposes it externally over HTTPS (`https://jenkins.dvankevich.pp.ua`) through the Multi-AZ `ingress-nginx` controller and `cert-manager` (`letsencrypt-prod`), avoiding the cost of an extra AWS LoadBalancer.
- **Persistent Storage**: Provisions a dedicated `10Gi` AWS EBS volume via the cluster's `ebs-gp3` `StorageClass` (`persistence.storageClass = "ebs-gp3"`) to persist `/var/jenkins_home` across pod restarts.
- **Declarative JCasC & Seed Job (`values.yaml` & `secrets.yaml`)**:
  - Injects `module.ecr.repository_url` dynamically via `templatefile` as a global Jenkins environment variable (`ECR_REPO_URL`) so `Jenkinsfile` never hardcodes AWS account IDs or registry URLs.
  - Loads the Jenkins admin password and GitHub Fine-grained Personal Access Token (`github-token`) from the gitignored `modules/jenkins/secrets.yaml` file.
  - Automatically configures `seed-job` using the `job-dsl` plugin to generate the `django-wagtail-ci` pipeline targeting `https://github.com/dvankevich/my-microservice-project.git` (`lesson-4/mysite/Jenkinsfile`).

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

Ensure `modules/jenkins/secrets.yaml` has been created from `secrets.yaml.example`, then preview the execution plan:

```bash
terraform plan
```

### Apply

Provision or update the infrastructure in AWS:

```bash
terraform apply
```

*(Note: When provisioning a brand-new cluster from scratch, `kubernetes_manifest` in `module.cluster_addons` requires the `cert-manager.io/v1` CRD to exist before planning. Deploy core AWS resources and `cert-manager` first via `terraform apply -target=module.vpc -target=module.ecr -target=module.eks -target=module.cluster_addons.helm_release.cert_manager`, apply `charts/django-app/templates/storageclass.yaml`, prepare `modules/jenkins/secrets.yaml`, and then run `terraform apply` to finish deploying `module.cluster_addons` and `module.jenkins`.)*

## Build and Push Django Docker Image to ECR (Manual Bootstrap)

Before building the initial image, ensure `lesson-4/mysite/mysite/settings/docker.py` configures HTTPS proxy headers and reads `CSRF_TRUSTED_ORIGINS` from the environment so Django 6.1 allows `POST` requests (such as `/admin/login/`) behind `ingress-nginx`:

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

### 3. Build and Push the Docker Image

Navigate to `lesson-4/mysite`, build the image targeting `linux/amd64`, and push it to ECR:

```bash
cd ../lesson-4/mysite
docker build --platform linux/amd64 -t "$ECR_REPO_URL:latest" .
docker push "$ECR_REPO_URL:latest"
aws ecr list-images --repository-name "$ECR_REPO_NAME" --region "$AWS_REGION"
cd ../../lesson-7
```

*(Once Jenkins is deployed, subsequent image builds and ECR pushes are automated through the `django-wagtail-ci` Kaniko pipeline.)*

## Deploy Ingress, TLS (`cert-manager`), and Django Application to EKS

The `charts/django-app` Helm chart separates non-sensitive configuration (`ConfigMap` via `values.yaml`) from sensitive credentials (`Kubernetes Secret` via `secrets.yaml`), provisions an encrypted `gp3` AWS EBS volume via `PersistentVolumeClaim` (`subPath: pgdata`, `Recreate` deployment strategy), and supports both direct L4 `LoadBalancer` access and L7 HTTPS termination via `ingress-nginx` and Let's Encrypt.

### 1. Configure `kubectl` for EKS

Update your local kubeconfig to connect to the `eks-cluster-demo` cluster and verify all nodes are `Ready`:

```bash
aws eks update-kubeconfig --region "$AWS_REGION" --name eks-cluster-demo
kubectl get nodes -L topology.kubernetes.io/zone
```

### 2. Verify `cluster-addons` and Configure DNS

Verify that the Multi-AZ `ingress-nginx-controller` pods are running across distinct Availability Zones and that `letsencrypt-prod` `ClusterIssuer` is `Ready`:

```bash
kubectl get pods -n ingress-nginx -o wide
kubectl get clusterissuer
```

Retrieve the `ingress-nginx` AWS LoadBalancer DNS hostname from Terraform outputs:

```bash
terraform output -raw ingress_elb_hostname
```

Configure DNS for your application domain (`django-app.dvankevich.pp.ua`):

- **Recommended (`CNAME` record):** Point `django-app` to the `ingress_elb_hostname` (`<id>.eu-central-1.elb.amazonaws.com`).
- **Alternative (`A` record):** Resolve the ELB's current IPv4 addresses with `dig +short <ingress_elb_hostname>` and add them as `A` records.

Verify DNS propagation before issuing certificates:

```bash
dig +short django-app.dvankevich.pp.ua
```

### 3. Prepare Local Secrets File

Copy the example secrets template and populate your actual `SECRET_KEY` and `POSTGRES_PASSWORD`. All `**/secrets.yaml` files are excluded via `.gitignore` so credentials are never committed to version control:

```bash
cp charts/django-app/secrets.yaml.example charts/django-app/secrets.yaml
# Edit charts/django-app/secrets.yaml with your actual credentials
```

### 4. Validate and Install the Helm Chart (`LoadBalancer` + `Ingress`)

In `charts/django-app/values.yaml`, `service.type` is set to `LoadBalancer` by default to expose a direct L4 AWS ELB on port `80 -> 8000` (satisfying project compliance requirements), while `ingress.enabled: true` simultaneously routes HTTPS traffic (`https://django-app.dvankevich.pp.ua`) through the Multi-AZ `ingress-nginx` controller and `cert-manager`:

```yaml
service:
  type: LoadBalancer # Switch: "LoadBalancer" (default) or "ClusterIP" (Ingress-only mode)
  port: 80
  targetPort: 8000
```

Lint the chart and deploy the release into the `wagtail` namespace, passing both `values.yaml` and your local `secrets.yaml`:

```bash
helm lint ./charts/django-app

helm upgrade --install django-app ./charts/django-app \
  -n wagtail \
  --create-namespace \
  -f ./charts/django-app/values.yaml \
  -f ./charts/django-app/secrets.yaml
```

*(To deploy without creating a separate application ELB and route traffic solely through `ingress-nginx`, override the switch with `--set service.type=ClusterIP`. If updating an existing deployment after pushing a new image with the `:latest` tag, run `kubectl rollout restart deployment/django-app-django -n wagtail`.)*

### 5. Verify the Deployment, LoadBalancer, and TLS Certificate

Check that the `PersistentVolumeClaim` is `Bound`, all pods are `Running`, `django-app-django` has an `EXTERNAL-IP` LoadBalancer, and the TLS `Certificate` reaches `READY: True` (takes ~1–2 minutes for the Let's Encrypt HTTP-01 challenge):

```bash
kubectl get pvc,pv,pods,svc,ingress,certificate,hpa,secret -n wagtail
```

Verify both L7 HTTPS access (via `ingress-nginx`) and direct L4 HTTP access (via the `LoadBalancer` service):

```bash
curl -I https://django-app.dvankevich.pp.ua
curl -I http://$(kubectl get svc django-app-django -n wagtail -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

### 6. Create Django/Wagtail Superuser

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

> **Load Testing:** For instructions and automated verification scripts covering TLS, High Availability, Zero-Downtime Rolling Updates, and HPA scaling, see [`LOAD_TESTING.md`](./LOAD_TESTING.md) and [`AUTOMATED_TESTING.md`](./AUTOMATED_TESTING.md).

## Pod Distribution & High Availability (`topologySpreadConstraints`)

By default, the Kubernetes scheduler places new pods based solely on available node resources. During pod recreation (self-healing) or HPA scale-out events, multiple Django replicas can end up scheduled on the same worker node, reducing fault tolerance if that node or Availability Zone fails.

To prevent single-node concentration, both the Ingress layer (`modules/cluster-addons/main.tf`, spreading `ingress-nginx-controller` across `topology.kubernetes.io/zone`) and the application layer (`charts/django-app/templates/deployment.yaml`) enforce `topologySpreadConstraints`:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: {{ .Release.Name }}-django
```

- **`maxSkew: 1`:** Limits the difference in Django pod counts between any two worker nodes to at most `1` (distributing pods as `1 + 1` at 2 replicas, `2 + 2` at 4 replicas, and `3 + 3` at 6 replicas).
- **`topologyKey: kubernetes.io/hostname`:** Spreads pods evenly across distinct EKS worker nodes. Because the node group spans multiple public subnets (`eu-central-1a`, `eu-central-1b`, `eu-central-1c`), this also provides Multi-AZ resilience.
- **`whenUnsatisfiable: ScheduleAnyway`:** Applies a soft scheduling constraint so pods are evenly balanced during normal operation and self-healing, while still allowing replicas to run on a single surviving node if another node becomes unavailable.

Verify that Django and Ingress replicas are scheduled across distinct nodes and Availability Zones:

```bash
kubectl get pods -n wagtail -o wide
kubectl get pods -n ingress-nginx -o wide
```

## Deploy Jenkins CI/CD Server & Kaniko ECR Pipeline

Jenkins is provisioned via `./modules/jenkins`, integrating IRSA for passwordless ECR image pushes, JCasC for declarative credentials and job generation, and Kubernetes pod agents running Kaniko.

### 1. Configure DNS for Jenkins

In your DNS provider for `dvankevich.pp.ua`, create a `CNAME` record for `jenkins` pointing to the same `ingress_elb_hostname` (`<id>.eu-central-1.elb.amazonaws.com`) used by `django-app`:

```bash
terraform output -raw ingress_elb_hostname
dig +short jenkins.dvankevich.pp.ua
```

### 2. Ensure Sufficient Cluster Capacity (3 Nodes)

If upgrading an existing 2-node cluster, ensure `desired_size = 3` and `max_size = 4` are set in `main.tf` and scale the active node count via AWS CLI so there are enough pod slots and memory for the Jenkins controller and dynamic Kaniko agent pods alongside Django, PostgreSQL, and Multi-AZ `ingress-nginx`:

```bash
terraform apply -target=module.eks

aws eks update-nodegroup-config \
  --region eu-central-1 \
  --cluster-name eks-cluster-demo \
  --nodegroup-name general \
  --scaling-config minSize=2,maxSize=4,desiredSize=3

kubectl get nodes
```

### 3. Ensure `ebs-gp3` StorageClass Exists

The `ebs-gp3` `StorageClass` is created by the `django-app` Helm chart. If deploying Jenkins before installing `django-app`, apply the `StorageClass` manifest standalone:

```bash
kubectl apply -f charts/django-app/templates/storageclass.yaml
```

### 4. Configure Local Jenkins Secrets (`secrets.yaml`)

1. Generate a **Fine-grained Personal Access Token** in GitHub (*Settings → Developer settings → Personal access tokens → Fine-grained tokens*) scoped only to `dvankevich/my-microservice-project` with **`Contents: Read-only`** permission.
2. Copy the example secrets template and populate your Jenkins admin password and GitHub PAT:

```bash
cp modules/jenkins/secrets.yaml.example modules/jenkins/secrets.yaml
# Edit modules/jenkins/secrets.yaml with your admin password and github_pat_... token
```

### 5. Apply Terraform to Deploy Jenkins & IRSA

Initialize the providers and apply the configuration:

```bash
terraform init
terraform apply
```

*(Note: If the `jenkins` namespace already exists in the cluster from a prior manual installation, import it into state first via `terraform import module.jenkins.kubernetes_namespace_v1.jenkins jenkins` before running `terraform apply`.)*

### 6. Verify Jenkins Pod, IRSA ServiceAccount, and TLS Certificate

Confirm that `jenkins-sa` carries the IRSA role annotation, the `10Gi` EBS `PersistentVolumeClaim` is `Bound`, `jenkins-0` reaches `2/2 Running`, and the TLS `Certificate` is `READY: True`:

```bash
kubectl get sa jenkins-sa -n jenkins -o yaml
kubectl get pvc,pv,pods,svc,ingress,certificate -n jenkins
```

### 7. Generate and Run the CI Pipeline (`django-wagtail-ci`)

1. Open `https://jenkins.dvankevich.pp.ua` in your browser and sign in as `admin`.
2. Open **`seed-job`** and click **Build Now** (if prompted for script approval, approve it under *Manage Jenkins → In-process Script Approval* and re-run `seed-job`).
3. Return to the dashboard, open the newly generated **`django-wagtail-ci`** pipeline, and click **Build Now**. Jenkins will spawn an ephemeral Kubernetes pod with `serviceAccountName: jenkins-sa` (scheduled away from `jenkins-0` via `podAntiAffinity` and optimized with `--snapshot-mode=redo --use-new-run` to stay within `t3.small` memory limits), build `lesson-4/mysite/Dockerfile` via Kaniko, and push the resulting image (`:latest` and `:<BUILD_NUMBER>`) to Amazon ECR.
4. Verify the pushed image tags in ECR:

```bash
aws ecr describe-images \
  --repository-name lesson-5-ecr \
  --region eu-central-1 \
  --query 'sort_by(imageDetails,& imagePushedAt)[*].{Tags:imageTags,PushedAt:imagePushedAt}' \
  --output table
```

## Cleanup

Remove the `django-app` Helm release (which also deletes the `django-app-django` AWS LoadBalancer) and `metrics-server` first, then destroy the Terraform-managed `jenkins` module and its EBS `PersistentVolumeClaim`, and finally run `terraform destroy` to clean up `cluster_addons` (including the `ingress-nginx` ELB), EKS, ECR, and VPC:

```bash
helm uninstall django-app -n wagtail
kubectl delete pvc django-app-postgres-pvc -n wagtail
helm uninstall metrics-server -n kube-system

terraform destroy -target=module.jenkins
kubectl delete pvc -n jenkins --all

terraform destroy
```
