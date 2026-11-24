# Automated Infrastructure & Load Testing Script (`run-tests.sh`)

`run-tests.sh` is an end-to-end verification script for the `django-app` deployment on Amazon EKS. It automates TLS checks, high availability and self-healing tests, zero-downtime rolling updates, external HTTPS load benchmarking with Horizontal Pod Autoscaler (HPA) monitoring, and optional PostgreSQL EBS volume persistence verification, compiling all results into a timestamped Markdown report.

## Prerequisites

### 1. Required CLI Tools

Ensure the following command-line utilities are installed and available in your `PATH`:

| Tool | Purpose | Installation Example (Ubuntu / Debian) |
| :--- | :--- | :--- |
| `kubectl` | Inspecting pods, HPA metrics, and triggering rollouts | `sudo snap install kubectl --classic` |
| `curl` | Probing HTTP redirects and endpoint availability | `sudo apt install -y curl` |
| `openssl` | Inspecting the live Let's Encrypt TLS certificate chain | `sudo apt install -y openssl` |
| `hey` | Generating concurrent external HTTPS load | `sudo apt install -y hey` |

### 2. Cluster & Application Requirements

* `kubectl` context configured to point to the `eks-cluster-demo` cluster (`aws eks update-kubeconfig --region eu-central-1 --name eks-cluster-demo`).
* `metrics-server` running in `kube-system` so HPA reports live CPU utilization.
* `ingress-nginx` and `cert-manager` deployed with an active TLS certificate for the target domain.

## Configuration

The target environment parameters are defined at the top of `run-tests.sh` and can be adjusted if deploying to a different namespace or domain:

```bash
NAMESPACE="wagtail"
DOMAIN="django-app.dvankevich.pp.ua"
URL="https://${DOMAIN}/"
DEPLOYMENT="django-app-django"
POSTGRES_DEPLOYMENT="django-app-postgres"
HPA_NAME="django-app-django-hpa"
```

## Usage

### 1. Grant Execute Permissions

```bash
cd lesson-7
chmod +x run-tests.sh
```

### 2. Run Modes

* **Standard Full Suite (~9–10 minutes):**
  Runs all application checks, executes the 3-minute `hey` load test, and waits up to 7 minutes for Kubernetes HPA to complete its 5-minute scale-down stabilization cooldown back to `2` replicas:
  ```bash
  ./run-tests.sh
  ```

* **Fast Mode (`--fast`, ~4 minutes):**
  Runs all checks and the 3-minute load test, but skips waiting for the post-load HPA scale-down window:
  ```bash
  ./run-tests.sh --fast
  ```

* **Include PostgreSQL Persistence Check (`--with-db`):**
  Adds Stage 5, which restarts `django-app-postgres` (using the `Recreate` strategy) and verifies that the AWS EBS `PersistentVolumeClaim` cleanly re-attaches in `Bound` state. *(Note: restarting the single PostgreSQL pod causes brief database unavailability during volume remounting.)*
  ```bash
  ./run-tests.sh --with-db
  ```

* **Help Menu:**
  ```bash
  ./run-tests.sh --help
  ```

## Test Stages Breakdown

1. **TLS Certificate & HTTP Redirect Check:**
   Sends an unencrypted request to `http://<DOMAIN>/` to confirm an automatic `301`/`308` redirect to HTTPS, and queries port `443` via `openssl s_client` to record the certificate issuer, subject, and expiration dates.
2. **High Availability & Self-Healing:**
   Checks `kubectl get pods -o wide` to confirm that `django-app-django` replicas are scheduled across multiple worker nodes, then deletes one active pod and measures the time required for the ReplicaSet controller to restore full readiness.
3. **Zero-Downtime Rolling Update:**
   Starts a background HTTP probe loop polling the HTTPS endpoint every `0.5s` while executing `kubectl rollout restart deployment/django-app-django`, verifying that `0` non-`200` responses occur during pod replacement.
4. **External HTTPS Load Test & HPA Scaling:**
   Captures baseline HPA metrics, runs `hey -z 3m -c 30` against the public HTTPS URL, polls `currentReplicas` every `15s` to record peak scale-out, and (unless `--fast` is set) monitors scale-down back to `minReplicas: 2`.
5. **PostgreSQL EBS Persistence Check (Optional via `--with-db`):**
   Triggers a rollout restart of `django-app-postgres` and confirms that the `5Gi` `ebs-gp3` `PersistentVolumeClaim` remains `Bound` without volume attachment conflicts.

## Output Report

Upon completion, the script writes a self-contained Markdown report to the current directory named:

```text
test-report-YYYY-MM-DD_HH-MM.md
```

> **Tip:** If you run the script frequently during development, consider adding `test-report-*.md` to `lesson-7/.gitignore` so ad-hoc test artifacts are only committed intentionally.

## Taskfile Integration Example

To trigger the test suite via `Taskfile.yml`, add the following tasks:

```yaml
version: '3'

tasks:
  test:
    dir: lesson-7
    desc: Run automated EKS verification suite (fast mode)
    cmds:
      - ./run-tests.sh --fast

  test:full:
    dir: lesson-7
    desc: Run full EKS verification suite including HPA scale-down and DB restart
    cmds:
      - ./run-tests.sh --with-db
```