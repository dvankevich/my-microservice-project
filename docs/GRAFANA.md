# Робота з Grafana у проєкті (`my-microservice-project`)

Цей посібник описує архітектуру, доступ, налаштування джерела даних, імпорт готових дашбордів і створення власних візуалізацій у **Grafana** для нашого EKS-кластера (`5 x t3.small`, `eu-central-1`).

---

## 1. Як розгорнуто Grafana в інфраструктурі

Grafana інтегрована безпосередньо в Terraform-модуль **`./modules/monitoring`** (`monitoring.tf` + `grafana-values.yaml`) і працює в неймспейсі `monitoring`:

* **HTTPS-доступ та TLS:** трафік на `https://grafana.dvankevich.pp.ua` маршрутизується через Multi-AZ `ingress-nginx` із автоматичним випуском сертифіката Let's Encrypt (`ClusterIssuer: letsencrypt-prod`, секрет `grafana-tls`). Постійний `kubectl port-forward` не потрібен.
* **Постійне сховище (`ebs-gp3`):** підключено том `2Gi` (`/var/lib/grafana`), де зберігається база SQLite (`grafana.db`) з усіма імпортованими дашбордами, налаштуваннями та зміненими паролями.
* **Керування обліковими даними:** під час першого `terraform apply` ресурс `random_password.grafana_admin` генерує пароль і зберігає його в Kubernetes Secret `grafana-admin-secret`. Під час наступних `helm upgrade` чи редеплоїв пароль **не змінюється**, оскільки він зафіксований у Terraform State (`S3`) та у `grafana.db` на EBS-диску.
* **Попередньо підключений Prometheus:** через `datasources.yaml` у Grafana автоматично додано джерело **`Prometheus (main)`** за внутрішньою адресою `http://prometheus-server.monitoring.svc.cluster.local`.
* **Бюджет ресурсів під `t3.small`:** `requests: 50m CPU / 128Mi RAM`, `limits: 250m CPU / 256Mi RAM`.

---

## 2. Вхід у веб-інтерфейс та перевірка Prometheus Data Source

### Крок 1. Отримайте пароль адміністратора

Виконайте в терміналі команду (або візьміть її з `terraform output -raw grafana_admin_password_command`):

```bash
kubectl get secret -n monitoring grafana-admin-secret \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

### Крок 2. Увійдіть у Grafana

1. Відкрийте **`https://grafana.dvankevich.pp.ua`**.
2. Введіть логін **`admin`** та отриманий пароль.
3. *(За бажанням)* У меню профілю (правий верхній кут → **Profile → Change password**) задайте власний зручний пароль — він збережеться на EBS-томі `ebs-gp3`.

### Крок 3. Перевірте підключення до Prometheus

1. У лівому меню відкрийте **Connections → Data sources** (або **Administration → Data sources**).
2. Натисніть **`Prometheus (main)`** (позначене як `default`).
3. Переконайтеся, що у полі **Connection → Prometheus server URL** вказано:
   ```text
   http://prometheus-server.monitoring.svc.cluster.local
   ```
4. Прокрутіть сторінку вниз і натисніть **Save & test** — має з'явитися зелене повідомлення **`Successfully queried the Prometheus API`**.

---

## 3. Імпорт готових дашбордів з Grafana.com

Найшвидший спосіб отримати повну картину по вузлах EC2 і подах Kubernetes — імпортувати перевірені спільнотою дашборди.

### Як імпортувати дашборд

1. У правому верхньому куті (або в лівому меню **Dashboards**) натисніть **`+` → Import dashboard**.
2. Введіть числовий **ID дашборду** у поле *Import via grafana.com* і натисніть **Load**.
3. У полі вибору джерела даних оберіть **`Prometheus (main)`**.
4. Натисніть **Import** та збережіть дашборд (іконка дискети у верхньому меню).

### Рекомендовані дашборди для нашого кластера

| ID дашборду | Назва | Що візуалізує у нашому проєкті |
| :--- | :--- | :--- |
| **`1860`** | **Node Exporter Full** | Детальні системні метрики всіх 5 інстансів `t3.small` (`eu-central-1a/b/c`): завантаження CPU, використана/доступна RAM, IOPS томів EBS, мережевий трафік. |
| **`15757`** | **Kubernetes / Views / Global** | Загальний огляд кластера EKS (`v1.37`): сумарне споживання CPU/RAM, кількість запущених подів, вузлів та мережевих пакетів. |
| **`15760`** | **Kubernetes / Views / Pods** | Зручна фільтрація за неймспейсами (`wagtail`, `jenkins`, `argocd`, `monitoring`, `ingress-nginx`) із відображенням рестартів, CPU та RAM кожного поду. |

---

## 4. Створення власних панелей (PromQL для EKS та `t3.small`)

Щоб додати власну панель: відкрийте **Dashboards → New → New dashboard → Add visualization**, оберіть **`Prometheus (main)`**, перемкніть редактор запиту в режим **Code** (праворуч) і вставте потрібний PromQL-запит.

### Особливості метрик у нашому AWS EKS кластері

* **Накопичувальні лічильники CPU:** `container_cpu_usage_seconds_total` зростає постійно з моменту старту контейнера, тому її завжди потрібно передавати у функцію `rate(...[5m])` та відфільтровувати службові pause-контейнери (`container!=""`).
* **Особливості EC2 (`t3.small`):** на віртуальних машинах AWS EC2 відсутні апаратні датчики температури (`node_hwmon_temp_celsius` не повертатиме даних), а мітка типу інстансу (`eks_amazonaws_com_capacityType`) знаходиться в метриці `kube_node_labels`, а не в метриках cAdvisor.

### Готові PromQL-запити для наших сервісів

1. **Споживання CPU подами Django (`namespace="wagtail"`, у ядрах vCPU):**
   ```promql
   sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="wagtail", container!=""}[5m]))
   ```
   *Тип графіка:* **Time series**, одиниця виміру (*Unit*): `Misc → short` (або `cores`).

2. **Фактичне використання RAM подами Django (у MiB):**
   ```promql
   sum by (pod) (container_memory_working_set_bytes{namespace="wagtail", container!=""}) / 1024 / 1024
   ```
   *Одиниця виміру (Unit):* `Data → mebibytes (MiB)`. Дозволяє бачити наближення до ліміту `400 MiB`, заданого в `charts/django-app/values.yaml`.

3. **Контроль ліміту подів на вузлах `t3.small` (максимум 11 подів на вузол):**
   ```promql
   count by (node) (kube_pod_info{node!=""})
   ```
   *Тип графіка:* **Bar gauge** або **Stat**. Якщо на якійсь ноді значення підходить до `10–11`, планувальник не зможе розмістити на ній нові поди HPA чи Kaniko.

4. **Реальна зайнята RAM на кожній EC2-ноді (у MiB):**
   ```promql
   (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024 / 1024
   ```

5. **Зарезервована пам'ять (`requests.memory`) по кожній ноді (у MiB):**
   ```promql
   sum by (node) (kube_pod_container_resource_requests{resource="memory"}) / 1024 / 1024
   ```

6. **Пікове споживання RAM під час збірок Jenkins Kaniko (у MiB):**
   ```promql
   sum by (pod, container) (container_memory_working_set_bytes{namespace="jenkins", container!=""}) / 1024 / 1024
   ```

---

## 5. Збереження власних дашбордів у Git (Backup)

Хоча дашборди зберігаються на EBS-томі `ebs-gp3`, у разі повного видалення кластера (`terraform destroy`) диск буде видалений. Щоб зберегти власний дашборд у репозиторії:

1. Відкрийте створений дашборд у Grafana та натисніть **Share → Export** (іконка експорту у верхній панелі).
2. Увімкніть перемикач **Export for sharing externally** (щоб дашборд не прив'язувався до внутрішнього UID джерела даних) і натисніть **Save to file**.
3. Збережіть JSON-файл у каталог `docs/dashboards/` і зафіксуйте в Git з тегом `[skip ci]`.