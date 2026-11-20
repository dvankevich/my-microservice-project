# Load Testing & HPA Autoscaling Verification

This document describes how to monitor resource consumption and run load tests against the Django/Wagtail application in Amazon EKS to verify that the `HorizontalPodAutoscaler` (`django-app-django-hpa`) scales pods from **2 to 6 replicas** when average CPU utilization exceeds **70%**.

## Scaling Threshold Overview

* **Deployment:** `django-app-django` (namespace: `wagtail`)
* **Pod CPU Request:** `100m` (`0.1` vCPU)
* **Pod CPU Limit:** `400m` (`0.4` vCPU)
* **Target CPU Utilization:** `70%` of request (`70m` per pod)
* **Replica Range:** `minReplicas: 2` — `maxReplicas: 6`

When average CPU usage across running Django pods stays above `70m` (`70%`), the HPA controller calculates the desired replica count and scales up (up to `6` pods). Once traffic stops, Kubernetes waits for the default stabilization window (~5 minutes) before scaling back down to `2` replicas.

---

## Real-Time Monitoring

Before starting a load test, open a separate terminal window to observe HPA metrics, replica counts, and pod scheduling in real time:

```bash
# Refresh HPA status and pod list every 2 seconds
watch -n 2 kubectl get hpa,pods -n wagtail
```

*(Note: `kubectl get ... -w` only supports a single resource type at a time, so use either `watch -n 2 kubectl get hpa,pods -n wagtail` or separate terminals for `kubectl get hpa -n wagtail -w` and `kubectl get pods -n wagtail -w`.)*

To inspect exact millicores (`CPU(cores)`) and memory usage per pod:

```bash
kubectl top pods -n wagtail
```

---

## Scenario 1: In-Cluster HTTP Load Generator (`busybox`)

This lightweight test runs a temporary pod inside the `wagtail` namespace and sends continuous HTTP requests directly to the internal `ClusterIP` service (`http://django-app-django`), bypassing external network latency.

### 1. Start the Load Generator

```bash
kubectl run load-generator \
  --rm -it \
  --image=busybox:1.36 \
  --restart=Never \
  -n wagtail -- \
  /bin/sh -c "while true; do wget -q -O- http://django-app-django > /dev/null; done"
```

*(Tip: To generate heavier load faster, launch 2–3 parallel worker loops inside the container: `for i in 1 2 3; do (while true; do wget -q -O- http://django-app-django > /dev/null; done) & done; wait`.)*

### 2. Observe Scale-Up Behavior

Within **30–90 seconds**:
1. `TARGETS` in `kubectl get hpa -n wagtail` rises above `70%` (e.g., `cpu: 145%/70%`).
2. `REPLICAS` increases from `2` toward `6`.
3. New `django-app-django-*` pods transition through `ContainerCreating` to `1/1 Running` across the available worker nodes.

### 3. Stop the Test and Observe Scale-Down

Press `Ctrl+C` in the load generator terminal. Because `--rm` is set, Kubernetes automatically deletes the `load-generator` pod. Over the next **5 minutes**, `TARGETS` will drop back to `1%/70%` and `REPLICAS` will return to `2`.

---

## Additional Load Testing Examples

*(Placeholder for future external HTTPS benchmarks against `https://django-app.dvankevich.pp.ua` using tools such as `k6`, `hey`, `wrk`, or `Locust`.)*