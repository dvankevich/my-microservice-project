# Prometheus UI & PromQL Practical Guide

This guide explains how to navigate the Prometheus web interface, inspect Kubernetes Service Discovery targets, and run useful PromQL queries tailored to this cluster (`eks-cluster-demo`, `t3.small` worker nodes, and the `wagtail`, `jenkins`, `argocd`, `ingress-nginx`, and `monitoring` namespaces).

---

## 1. Accessing the Prometheus Web UI

Prometheus is deployed as an internal `ClusterIP` service inside the `monitoring` namespace. Start a local port-forward tunnel from the repository root:

```bash
$(terraform output -raw prometheus_port_forward_command)
# Equivalent command:
# kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

Open **`http://localhost:9090`** in your browser.

---

## 2. Key Sections in the Prometheus UI

### A. `Status → Target health` (First Place to Check)

Shows every HTTP metrics endpoint Prometheus actively scrapes, grouped by `job` name:

* **State (`UP` / `DOWN` / `UNKNOWN`)**: Confirms whether the last scrape succeeded (`HTTP 200`).
* **Endpoint & Labels**: Shows the target IP/port and attached metadata labels (`instance`, `job`, `node`, `namespace`, `pod`).
* **Last Scrape & Scrape Duration**: Useful for spotting slow exporters or network timeouts.

**Default Active Jobs in This Cluster:**

| Job Name | Source | What It Collects |
| :--- | :--- | :--- |
| `kubernetes-apiservers` | EKS Control Plane (`https://10.0.x.x:443/metrics`) | API request latency, error rates, etcd/controller metrics |
| `kubernetes-nodes` | Kubelet API proxy per EC2 node | Node-level kubelet health, pod counts, volume stats (`t3.small`, `eu-central-1a/b/c`, `role="general"`) |
| `kubernetes-nodes-cadvisor` | cAdvisor embedded in Kubelet | Container CPU, memory working set, filesystem, and network I/O for every pod |
| `kubernetes-service-endpoints` | Services annotated with `prometheus.io/scrape: "true"` | `kube-state-metrics`, `prometheus-node-exporter`, and custom annotated services |
| `kubernetes-pods` | Pods annotated with `prometheus.io/scrape: "true"` | Application-level metrics exposed directly by pods (e.g., Django `/metrics`) |

### B. `Status → Service discovery`

Displays all Kubernetes resources discovered via `kubernetes_sd_config` **before** relabeling and filtering rules decide whether to scrape them:

* **Discovered Labels (`_meta_kubernetes_*`)**: Shows raw metadata returned by the Kubernetes API, such as `_meta_kubernetes_namespace="wagtail"`, `_meta_kubernetes_pod_label_app="django-app-django"`, and `_meta_kubernetes_pod_annotation_prometheus_io_scrape`.
* **Target Labels**: Shows the final labels preserved on time series after `relabel_configs` run.
* **Troubleshooting Tip**: If you add `prometheus.io/scrape: "true"` to a Pod or Service and it does not appear in **Target health**, open **Service discovery → `kubernetes-pods`** to verify that Prometheus sees the pod and check how its annotations were relabeled.

### C. `Graph` & `Table` (Query Explorer)

* **`Table` tab**: Evaluates an **instant vector** at a single timestamp—best for checking current cluster state (e.g., current RAM per pod, pod counts per node, container restarts).
* **`Graph` tab**: Plots a **range vector** over time (e.g., `15m`, `1h`, `6h`)—best for visualizing CPU spikes during load tests (`tests/run-tests.sh`) or Kaniko image builds.

### D. `Status → TSDB Status` & `Runtime & Build Information`

* Shows total active time series, head block memory footprint, and disk usage on the `5Gi` `ebs-gp3` volume (`retention: 3d`).

---

## 3. Useful PromQL Queries for This Project

### A. EKS Node Capacity & `t3.small` Constraints

Each `t3.small` worker node provides **2 GiB of RAM** and supports a maximum of **11 pods per node** (AWS VPC CNI ENI limit). These queries help monitor headroom across your 4 nodes:

1. **Memory Utilization (%) per Worker Node:**
   ```promql
   100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))
   ```

2. **Available RAM (in MiB) per Worker Node:**
   ```promql
   node_memory_MemAvailable_bytes / 1024 / 1024
   ```

3. **CPU Utilization (%) per Worker Node (5-minute average):**
   ```promql
   100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
   ```

4. **Scheduled Pods per Node vs. the 11-Pod `t3.small` ENI Limit:**
   ```promql
   count by (node) (kube_pod_info{node!=""})
   ```
   *(If any node approaches `10` or `11`, new pods—such as ephemeral Jenkins Kaniko agents or HPA scale-out replicas—may wait in `Pending`.)*

5. **PersistentVolume (EBS `ebs-gp3`) Disk Usage (%) for Jenkins (`10Gi`) & Prometheus (`5Gi`):**
   ```promql
   100 * (
     kubelet_volume_stats_used_bytes{namespace=~"jenkins|monitoring"}
     /
     kubelet_volume_stats_capacity_bytes{namespace=~"jenkins|monitoring"}
   )
   ```

---

### B. Django / Wagtail Application (`namespace="wagtail"`)

1. **Actual Memory Usage (MiB) per Django Pod vs. `400Mi` Limit:**
   ```promql
   sum by (pod) (
     container_memory_working_set_bytes{namespace="wagtail", container="django"}
   ) / 1024 / 1024
   ```

2. **CPU Utilization (%) Relative to `100m` Request (HPA Scaling Indicator):**
   HPA scales `django-app-django` when average CPU exceeds **70%** of the `100m` (`0.1` core) request:
   ```promql
   100 * (
     sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="wagtail", container="django"}[2m]))
     / 0.1
   )
   ```

3. **HPA Current vs. Desired Replicas Over Time (Run in `Graph` during `tests/run-tests.sh`):**
   ```promql
   kube_horizontalpodautoscaler_status_current_replicas{namespace="wagtail"}
   ```
   ```promql
   kube_horizontalpodautoscaler_status_desired_replicas{namespace="wagtail"}
   ```

4. **Pod Distribution Across Nodes (Verify `topologySpreadConstraints`):**
   ```promql
   count by (node) (kube_pod_info{namespace="wagtail", created_by_kind="ReplicaSet"})
   ```

---

### C. Jenkins CI & Argo CD GitOps (`jenkins` & `argocd`)

1. **Jenkins Controller & Ephemeral Kaniko Agent Memory Usage (MiB):**
   Kaniko builds have a `1450Mi` memory limit—plot this query in `Graph` during a CI build to inspect peak memory consumption:
   ```promql
   sum by (pod, container) (
     container_memory_working_set_bytes{namespace="jenkins", container=~"jenkins|kaniko|git|jnlp"}
   ) / 1024 / 1024
   ```

2. **Argo CD Components Memory Usage (MiB):**
   ```promql
   sum by (pod, container) (
     container_memory_working_set_bytes{namespace="argocd", container!=""}
   ) / 1024 / 1024
   ```

3. **Network Traffic (Receive / Transmit KB/s) for `ingress-nginx-controller`:**
   ```promql
   sum by (pod) (
     rate(container_network_receive_bytes_total{namespace="ingress-nginx"}[5m])
   ) / 1024
   ```

---

### D. Cluster Health, Restarts & Error Diagnostics

1. **Container Restarts in the Last Hour Across Project Namespaces:**
   ```promql
   increase(
     kube_pod_container_status_restarts_total{namespace=~"wagtail|jenkins|argocd|monitoring|ingress-nginx"}[1h]
   ) > 0
   ```

2. **Containers Terminated Due to Out-Of-Memory (`OOMKilled`):**
   ```promql
   kube_pod_container_status_last_terminated_reason{
     namespace=~"wagtail|jenkins|argocd|monitoring|ingress-nginx",
     reason="OOMKilled"
   } == 1
   ```

3. **Pods Currently Stuck in `Pending`, `Failed`, or `Unknown` Phase:**
   ```promql
   kube_pod_status_phase{phase=~"Pending|Failed|Unknown"} == 1
   ```

4. **Deployment Replica Shortfalls (Desired > Available):**
   ```promql
   kube_deployment_spec_replicas - kube_deployment_status_replicas_available > 0
   ```

---

## 4. Collecting Custom Application & External Metrics

### Option 1: Scrape Django Application Metrics (`/metrics`)

The `charts/django-app` Helm chart already supports `podAnnotations` in `templates/deployment.yaml`:

1. Add `django-prometheus` to `Django/requirements.txt` and configure its middleware/URL route (`/metrics`) in `Django/mysite/`.
2. Enable Prometheus pod annotations in `charts/django-app/values.yaml`:
   ```yaml
   podAnnotations:
     prometheus.io/scrape: "true"
     prometheus.io/port: "8000"
     prometheus.io/path: "/metrics"
   ```
3. Once synced by Argo CD, Prometheus automatically discovers every `django-app-django` pod under **Target health → `kubernetes-pods`** and collects HTTP request latency, status codes (`2xx`/`4xx`/`5xx`), and database query metrics.

### Option 2: Register External Targets via `monitoring-extras`

To scrape an external exporter (such as a PostgreSQL exporter or custom service reachable inside the VPC), add an entry to `modules/monitoring/charts/values.yaml` and run `terraform apply -target=module.monitoring`:

```yaml
customTargets:
  - name: postgres-exporter
    ip: 10.0.4.15
    port: 9187
    metricsPath: /metrics
```

This creates a headless `Service` and `Endpoints` object in `monitoring` with `prometheus.io/scrape: "true"`, which Prometheus picks up automatically via `kubernetes-service-endpoints`.