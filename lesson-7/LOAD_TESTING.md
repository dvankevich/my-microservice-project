# Load Testing Guide & HPA Verification (`django-app`)

This document describes how to verify **Horizontal Pod Autoscaler (HPA)** behavior for the `django-app-django` deployment on Amazon EKS and records actual load test results.

## HPA Configuration & Scaling Thresholds

The `charts/django-app` Helm chart defines an `autoscaling/v2` HPA resource (`django-app-django-hpa`) with the following parameters:

* **Target Deployment:** `django-app-django`
* **Minimum Replicas (`minReplicas`):** `2`
* **Maximum Replicas (`maxReplicas`):** `6`
* **Target CPU Utilization:** `70%`
* **Pod CPU Request:** `100m` (`0.1` vCPU) — scale-up triggers when average CPU usage across pods exceeds **`70m`** (`70%` of `100m`).
* **Pod CPU Limit:** `400m` (`0.4` vCPU)
* **Scale-Down Stabilization Window:** `300s` (5 minutes default in Kubernetes to prevent replica flapping).

## Monitoring Commands

Before starting a load test, open a separate terminal window to observe HPA metrics and pod lifecycle events in real time:

```bash
# Watch HPA targets, replica counts, and pod statuses every 2–10 seconds
watch -n 2 kubectl get hpa,pods -n wagtail

# Inspect live CPU and memory consumption per pod (requires metrics-server)
kubectl top pods -n wagtail

# View detailed HPA scaling decisions and events
kubectl describe hpa django-app-django-hpa -n wagtail
```

---

## Load Testing Scenarios

### Scenario 1: In-Cluster HTTP Load Generator (`busybox`)

Generates continuous internal HTTP requests directly to the `django-app-django` `ClusterIP` service without external network or ingress overhead:

```bash
kubectl run load-generator --rm -it --image=busybox:1.36 --restart=Never -n wagtail -- \
  /bin/sh -c "while true; do wget -q -O- http://django-app-django > /dev/null; done"
```

Press `Ctrl+C` to stop the load test; `--rm` automatically deletes the temporary `load-generator` pod.

### Scenario 2: External HTTPS Load Testing (Placeholder for Future Examples)

*Reserved for external load testing examples against `https://django-app.dvankevich.pp.ua` (e.g., using `hey`, `k6`, or `ab`) to test full end-to-end throughput through `ingress-nginx` and TLS termination.*

---

## Recorded Load Test Results (Scenario 1)

**Date:** November 20, 2026  
**Cluster:** `eks-cluster-demo` (`eu-central-1`, 2x `t3.small` worker nodes)  
**Namespace:** `wagtail`

### Summary Timeline

| Stage | Timestamp | CPU Utilization (`Target: 70%`) | Desired / Active Replicas | Observation |
| :--- | :--- | :---: | :---: | :--- |
| **1. Baseline** | `19:53:38` | `1% / 70%` | `2` | Idle state at `minReplicas: 2`. |
| **2. Load Spike** | `19:55:18` | `92% / 70%` | `2 -> 3+` | `load-generator` running for `41s`; CPU exceeds `70%`, HPA initiates scale-up (`24dwz` created). |
| **3. Sustained Load** | `19:56:33` | `57% / 70%` | `4` | HPA scales out to `4` pods (`24dwz`, `cddjz`, `lbg46`, `vcflh`), bringing per-pod average CPU down to `57%`. |
| **4. Load Stopped** | `19:58:24` | `18% / 70%` | `4` | `load-generator` removed; CPU drops to `18%`, replicas held at `4` during the 5-minute stabilization window. |
| **5. Scaled Down** | `20:05:26` | `1% / 70%` | `2` | After stabilization completes, HPA terminates extra pods and returns to `minReplicas: 2`. |

---

### Detailed Console Outputs

#### 1. Initial State (Baseline)

Two `django-app-django` pods running with minimal CPU utilization (`1%`):

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 19:53:38 2026

NAME                                                        REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 1%/70%   2         6         2          22h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          53m
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          14m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h12m
```

#### 2. Under Active Load (Scale-Up Triggered)

41 seconds after starting `load-generator`, average CPU climbs to `92%` (`> 70%` threshold), triggering HPA scale-up (`pod/django-app-django-9d4964c78-24dwz` is scheduled and running):

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 19:55:18 2026

NAME                                                        REFERENCE                      TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 92%/70%   2         6         2          22h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-24dwz      1/1     Running   0          15s
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          54m
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          16m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h14m
pod/load-generator                         1/1     Running   0          41s
```

#### 3. Sustained Load Stabilized at 4 Replicas

With `4` replicas handling the traffic, average CPU utilization drops to `57%` (`< 70%`), stabilizing the replica count without further unnecessary scale-out:

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 19:56:33 2026

NAME                                                        REFERENCE                      TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 57%/70%   2         6         4          22h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-24dwz      1/1     Running   0          89s
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          55m
pod/django-app-django-9d4964c78-lbg46      1/1     Running   0          74s
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          17m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h15m
pod/load-generator                         1/1     Running   0          115s
```

#### 4. Immediately After Stopping Load (Stabilization Window)

Once `load-generator` is terminated (`Ctrl+C`), CPU utilization drops to `18%`. All `4` replicas remain active while Kubernetes waits out the 5-minute scale-down cooldown period:

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 19:58:24 2026

NAME                                                        REFERENCE                      TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 18%/70%   2         6         4          22h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-24dwz      1/1     Running   0          3m20s
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          57m
pod/django-app-django-9d4964c78-lbg46      1/1     Running   0          3m5s
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          19m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h17m
```

#### 5. Post-Stabilization Scale-Down

Approximately 7 minutes after load removal, HPA scales the deployment back down to `minReplicas: 2` (`cpu: 1%/70%`):

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 20:05:26 2026

NAME                                                        REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 1%/70%   2         6         2          22h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          64m
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          26m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h24m
```