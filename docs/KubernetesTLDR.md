### 1. Ноди (Nodes) та ємність кластера

```bash
# Список усіх вузлів, їхній статус (Ready/NotReady) та версія Kubernetes
kubectl get nodes

# Детальніше: внутрішні/зовнішні IP, версія ОС та ядра
kubectl get nodes -o wide

# Зони доступності (AZ) та типи EC2-інстансів кожної ноди
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type

# Точна кількість нод у кластері
kubectl get nodes --no-headers | wc -l

# Повна інформація про ноду: доступні ресурси, ліміт подів та список запущених подів
kubectl describe node <node-name>

```

---

### 2. Поди (Pods) та їх підрахунок

```bash
# Усі поди в усіх неймспейсах
kubectl get pods -A

# Поди в конкретному неймспейсі з прив'язкою до IP та вузла
kubectl get pods -n <namespace> -o wide

# Загальна кількість подів у кластері
kubectl get pods -A --no-headers | wc -l

# Кількість подів у конкретному неймспейсі
kubectl get pods -n <namespace> --no-headers | wc -l

# Показати лише проблемні поди (Pending, CrashLoopBackOff, Error тощо)
kubectl get pods -A --field-selector=status.phase!=Running

# Підрахувати, скільки подів запущено на кожній ноді (контроль ліміту подів на вузол)
kubectl get pods -A -o wide --no-headers | awk '{print $8}' | sort | uniq -c

```

---

### 3. Споживання ресурсів (CPU / RAM / Requests & Limits)

```bash
# Поточне споживання CPU та RAM по нодах (потребує metrics-server)
kubectl top nodes

# Поточне споживання CPU та RAM подами в неймспейсі
kubectl top pods -n <namespace>

# Топ подів у всьому кластері за споживанням пам'яті (RAM)
kubectl top pods -A --sort-by=memory

# Топ подів у всьому кластері за споживанням процесора (CPU)
kubectl top pods -A --sort-by=cpu

# Зарезервовані ресурси (Requests та Limits у % від ємності) по кожній ноді
kubectl describe nodes | grep -A 5 "Allocated resources"

```

---

### 4. Автоскейлінг (HPA та Cluster Autoscaler)

```bash
# Стан Horizontal Pod Autoscaler (поточний CPU %, мін/макс та активні репліки)
kubectl get hpa -A

# Деталі роботи HPA та події масштабування
kubectl describe hpa <hpa-name> -n <namespace>

# Статус Cluster Autoscaler: межі minSize/maxSize та кандидати нод на видалення
kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml

# Останні рішення Cluster Autoscaler у логах
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=50

```

---

### 5. Контролери, мережа та диски

```bash
# Список усіх Deployments, StatefulSets та DaemonSets
kubectl get deploy,sts,ds -A

# Сервіси (ClusterIP, LoadBalancer) та правила маршрутизації Ingress
kubectl get svc,ingress -A

# Стан дисків та запитів на сховище (PVC / PV)
kubectl get pvc,pv -A

# Періодичні задачі (CronJob) та разові завдання (Job)
kubectl get cronjob,jobs -A

```

---

### 6. Діагностика, логи та швидке керування

```bash
# Останні 20 подій у кластері (помилки планування, перезапуски, проблеми з дисками)
kubectl get events -A --sort-by='.lastTimestamp' | tail -n 20

# Діагностика конкретного поду (причини статусу Pending або CrashLoopBackOff)
kubectl describe pod <pod-name> -n <namespace>

# Логи поду в реальному часі (додайте --previous, якщо контейнер впав і перезапустився)
kubectl logs -f <pod-name> -n <namespace>

# Відкрити інтерактивний термінал усередині контейнера
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Ручна зміна кількості реплік (наприклад, 0 для тимчасової зупинки)
kubectl scale deployment <deploy-name> --replicas=<N> -n <namespace>

# Перезапуск застосунку без простою (Zero-Downtime Rolling Restart)
kubectl rollout restart deployment <deploy-name> -n <namespace>

```
