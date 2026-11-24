# Load Testing Guide, HPA & High Availability Verification (`django-app`)

This document describes how to verify **Horizontal Pod Autoscaler (HPA)** behavior and **High Availability (HA) / Self-Healing** resilience for the `django-app-django` deployment on Amazon EKS, along with recorded test results.

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

Before starting a test, open a separate terminal window to observe HPA metrics, node placement, and pod lifecycle events in real time:

```bash
# Watch HPA targets, replica counts, and pod statuses every 2–10 seconds
watch -n 2 kubectl get hpa,pods -n wagtail

# Check pod-to-node distribution across Availability Zones
kubectl get pods -n wagtail -o wide

# Inspect live CPU and memory consumption per pod (requires metrics-server)
kubectl top pods -n wagtail

# View detailed HPA scaling decisions and events
kubectl describe hpa django-app-django-hpa -n wagtail
```

## Verification & Load Testing Scenarios

### Scenario 1: In-Cluster HTTP Load Generator (`busybox`)

Generates continuous internal HTTP requests directly to the `django-app-django` `ClusterIP` service without external network or ingress overhead:

```bash
kubectl run load-generator --rm -it --image=busybox:1.36 --restart=Never -n wagtail -- \
  /bin/sh -c "while true; do wget -q -O- http://django-app-django > /dev/null; done"
```

Press `Ctrl+C` to stop the load test; `--rm` automatically deletes the temporary `load-generator` pod.

### Scenario 2: External HTTPS Load Testing (`hey`)

Generates external concurrent HTTPS traffic through the full production ingress path (`Internet -> AWS ELB -> ingress-nginx (TLS) -> ClusterIP Service -> Django Pods`):

```bash
hey -z 3m -c 30 https://django-app.dvankevich.pp.ua/
```

* `-z 3m`: Runs the benchmark for 3 minutes (long enough to observe HPA scale-out and stabilization).
* `-c 30`: Maintains 30 concurrent worker connections.

### Scenario 3: Multi-Node Distribution & Self-Healing (`High Availability`)

Verifies that `django-app-django` replicas are scheduled across separate worker nodes/Availability Zones and that the ReplicaSet controller automatically replaces a terminated pod without service disruption:

```bash
# 1. Verify node placement across subnets/AZs
kubectl get pods -n wagtail -o wide

# 2. Simulate an unexpected pod crash by deleting one active Django replica
kubectl delete pod <django-pod-name> -n wagtail
```

---

## Recorded Load Test Results (Scenario 1 — In-Cluster `busybox`)

* **Date:** November 20, 2026
* **Cluster:** `eks-cluster-demo` (`eu-central-1`, 2x `t3.small` worker nodes)
* **Namespace:** `wagtail`

### Summary Timeline (Scenario 1)

| Stage | Timestamp | CPU Utilization (`Target: 70%`) | Desired / Active Replicas | Observation |
| ----- | ----- | ----- | ----- | ----- |
| **1. Baseline** | `19:53:38` | `1% / 70%` | `2` | Idle state at `minReplicas: 2`. |
| **2. Load Spike** | `19:55:18` | `92% / 70%` | `2 -> 3+` | `load-generator` running for `41s`; CPU exceeds `70%`, HPA initiates scale-up (`24dwz` created). |
| **3. Sustained Load** | `19:56:33` | `57% / 70%` | `4` | HPA scales out to `4` pods (`24dwz`, `cddjz`, `lbg46`, `vcflh`), bringing per-pod average CPU down to `57%`. |
| **4. Load Stopped** | `19:58:24` | `18% / 70%` | `4` | `load-generator` removed; CPU drops to `18%`, replicas held at `4` during the 5-minute stabilization window. |
| **5. Scaled Down** | `20:05:26` | `1% / 70%` | `2` | After stabilization completes, HPA terminates extra pods and returns to `minReplicas: 2`. |

### Detailed Console Outputs (Scenario 1)

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

---

## Recorded Load Test Results (Scenario 2 — External HTTPS via `hey`)

* **Date:** November 20, 2026
* **Cluster:** `eks-cluster-demo` (`eu-central-1`, 2x `t3.small` worker nodes)
* **Target Endpoint:** `https://django-app.dvankevich.pp.ua/` (via AWS ELB + `ingress-nginx` + Let's Encrypt TLS)
* **Command:** `hey -z 3m -c 30 https://django-app.dvankevich.pp.ua/`

### Summary Timeline (Scenario 2)

| Stage | Timestamp | CPU Utilization (`Target: 70%`) | Active Django Pods | Observation |
| ----- | ----- | ----- | ----- | ----- |
| **1. Baseline** | `20:12:39` | `1% / 70%` | `2` | Idle state before external test (`cddjz`, `vcflh`). |
| **2. Load Spike** | `20:13:40` | `115% / 70%` | `4` | CPU surges to `115%`; HPA scales from `2` to `4` pods (`6c9vf` and `kdwg2` added). |
| **3. Sustained Load** | `20:14:28` | `60% / 70%` | `4` | `4` pods absorb the 30 concurrent HTTPS connections at `60%` average CPU (`< 70%`). |
| **4. Load Stopped** | `20:16:41` | `1% / 70%` | `4` | Benchmark finishes (`181.9s`); CPU drops to `1%`, `4` pods held during stabilization cooldown. |
| **5. Scaled Down** | `20:21:03` | `1% / 70%` | `2` | Extra pods (`6c9vf`, `kdwg2`) terminated; deployment returns to `minReplicas: 2`. |

### HTTP Benchmark Summary (`hey`)

| Metric | Value | Notes |
| ----- | ----- | ----- |
| **Total Requests** | `2,311` | Completed in `181.90s` (`~3 minutes`) |
| **Success Rate (HTTP 200)** | `100%` (`2,311 / 2,311`) | **Zero `502`/`503`/`504` errors** during live pod scale-out |
| **Throughput** | `12.71 req/s` | Sustained across `30` concurrent connections |
| **Data Transferred** | `15.69 MB` (`6,790 B/req`) | Full HTML response over HTTPS |
| **Fastest / Average Latency** | `0.11s` / `2.35s` | Includes TLS handshake + Django + PostgreSQL query |
| **p50 / p95 / p99 Latency** | `1.01s` / `7.89s` / `8.50s` | Tail latency reflects initial queue saturation prior to scale-up |

#### Raw `hey` Output

```text
Summary:
  Total:	181.8955 secs
  Slowest:	8.9953 secs
  Fastest:	0.1099 secs
  Average:	2.3496 secs
  Requests/sec:	12.7051
  
  Total data:	15691690 bytes
  Size/request:	6790 bytes

Response time histogram:
  0.110 [1]	|
  0.998 [1129]	|■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  1.887 [377]	|■■■■■■■■■■■■■
  2.775 [102]	|■■■■
  3.664 [209]	|■■■■■■■
  4.553 [62]	|■■
  5.441 [37]	|■
  6.330 [10]	|
  7.218 [91]	|■■■
  8.107 [235]	|■■■■■■■■
  8.995 [58]	|■■


Latency distribution:
  10% in 0.3170 secs
  25% in 0.5069 secs
  50% in 1.0092 secs
  75% in 3.3832 secs
  90% in 7.5036 secs
  95% in 7.8949 secs
  99% in 8.5015 secs

Details (average, fastest, slowest):
  DNS+dialup:	0.0083 secs, 0.1099 secs, 8.9953 secs
  DNS-lookup:	0.0037 secs, 0.0000 secs, 0.2906 secs
  req write:	0.0001 secs, 0.0000 secs, 0.0006 secs
  resp wait:	2.3407 secs, 0.1095 secs, 8.9951 secs
  resp read:	0.0005 secs, 0.0000 secs, 0.0148 secs

Status code distribution:
  [200]	2311 responses
```

### Detailed Console Outputs (Scenario 2)

#### 1. Before External Load (Baseline)

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 20:12:39 2026

NAME                                                        REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 1%/70%   2         6         2          23h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          72m
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          33m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h31m
```

#### 2. Under External Load (CPU Spike to 115%, Scaled to 4 Pods)

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 20:13:40 2026

NAME                                                        REFERENCE                      TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 115%/70%   2         6         4          23h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-6c9vf      1/1     Running   0          20s
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          73m
pod/django-app-django-9d4964c78-kdwg2      1/1     Running   0          20s
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          34m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h32m
```

#### 3. Sustained External Load (CPU Stabilized at 60%)

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 20:14:28 2026

NAME                                                        REFERENCE                      TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 60%/70%   2         6         4          23h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-6c9vf      1/1     Running   0          68s
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          73m
pod/django-app-django-9d4964c78-kdwg2      1/1     Running   0          68s
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          35m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h33m
```

#### 4. Immediately After Stopping External Load

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 20:16:41 2026

NAME                                                        REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 1%/70%   2         6         4          23h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-6c9vf      1/1     Running   0          3m21s
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          76m
pod/django-app-django-9d4964c78-kdwg2      1/1     Running   0          3m21s
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          37m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h35m
```

#### 5. Post-Stabilization Scale-Down

Extra pods (`6c9vf` and `kdwg2`) are terminated once the stabilization window elapses, returning the active workload to `2` pods:

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 20:21:03 2026

NAME                                                        REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 1%/70%   2         6         4          23h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          80m
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          42m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h40m
```

---

## Recorded Resilience Test Results (Scenario 3 — High Availability & Self-Healing)

* **Date:** November 20, 2026
* **Cluster:** `eks-cluster-demo` (`eu-central-1`, Multi-AZ deployment across `eu-central-1a` and `eu-central-1b`)

### Summary Findings (Scenario 3)

| Verification Check | Result | Details |
| ----- | ----- | ----- |
| **Multi-AZ Node Placement** | **Passed** | Active Django replicas (`cddjz` and `vcflh`) scheduled on separate worker nodes in distinct Availability Zones (`10.0.2.0/24` and `10.0.1.0/24`). |
| **Pod Self-Healing** | **Passed** | After deleting `django-app-django-9d4964c78-vcflh`, Kubernetes scheduled replacement pod `django-app-django-9d4964c78-h4j7h` (`1/1 Running` within `17s`), maintaining `REPLICAS: 2` with zero downtime. |

### Detailed Console Outputs (Scenario 3)

#### 1. Multi-Node / Multi-AZ Pod Distribution

`kubectl get pods -n wagtail -o wide` confirms that the two baseline Django replicas are distributed across both worker nodes (`ip-10-0-2-95` in `eu-central-1b` and `ip-10-0-1-228` in `eu-central-1a`):

```text
kubectl get pods -n wagtail -o wide
NAME                                   READY   STATUS    RESTARTS   AGE     IP           NODE                                          NOMINATED NODE   READINESS GATES
django-app-django-9d4964c78-cddjz      1/1     Running   0          84m     10.0.2.170   ip-10-0-2-95.eu-central-1.compute.internal    <none>           <none>
django-app-django-9d4964c78-vcflh      1/1     Running   0          46m     10.0.1.69    ip-10-0-1-228.eu-central-1.compute.internal   <none>           <none>
django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h44m   10.0.1.150   ip-10-0-1-228.eu-central-1.compute.internal   <none>           <none>
```

#### 2. State Before Pod Termination (`20:26:02`)

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 20:26:02 2026

NAME                                                        REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 1%/70%   2         6         2          23h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          85m
pod/django-app-django-9d4964c78-vcflh      1/1     Running   0          47m
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h45m
```

#### 3. Automatic Pod Recovery (`20:27:28`)

Following manual termination of `pod/django-app-django-9d4964c78-vcflh`, the ReplicaSet controller immediately provisions replacement `pod/django-app-django-9d4964c78-h4j7h` (`1/1 Running`, `AGE: 17s`):

```text
Every 10,0s: kubectl get hpa,pods -n wagtail                                 v14: Fri Nov 20 20:27:28 2026

NAME                                                        REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/django-app-django-hpa   Deployment/django-app-django   cpu: 1%/70%   2         6         2          23h

NAME                                       READY   STATUS    RESTARTS   AGE
pod/django-app-django-9d4964c78-cddjz      1/1     Running   0          86m
pod/django-app-django-9d4964c78-h4j7h      1/1     Running   0          17s
pod/django-app-postgres-8578df859b-tbcrl   1/1     Running   0          5h46m
```