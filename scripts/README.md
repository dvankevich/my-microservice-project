# Керування CI/CD стеком (`cicd.sh`)

Скрипт для швидкої зупинки та запуску **Jenkins**, **Argo CD** та **Argo CD Image Updater** в кластері EKS без впливу на роботу продакшн-застосунку (`wagtail`). Дозволяє звільнити слоти подів та оперативну пам'ять у періоди, коли активна розробка не ведеться.

## Вимоги

- Встановлений `kubectl` з налаштованим і активним контекстом EKS-кластера.
- Права на масштабування `Deployment`, `StatefulSet` та керування `CronJob` у неймспейсах `jenkins` і `argocd`.

## Використання

Надайте скрипту права на виконання (одноразово):

```bash
chmod +x scripts/cicd.sh
```

Запуск:

```bash
./scripts/cicd.sh <команда>
```

| Команда | Опис |
| :--- | :--- |
| `start` | Запускає Jenkins, Argo CD та Image Updater і миттєво оновлює токен доступу до Amazon ECR. |
| `stop` | Масштабує Jenkins та Argo CD до `0` реплік і призупиняє `CronJob` оновлення ECR-токена. |
| `status` | Показує поточний стан вузлів EKS та подів у неймспейсах `jenkins`, `argocd` і `wagtail`. |
| `help` | Виводить коротку довідку щодо команд (`-h`, `--help`). |

## Особливості роботи

- **Збереження даних і продакшну (`stop`):** замість видалення ресурсів через `terraform destroy` скрипт обнуляє кількість реплік. Диск `ebs-gp3` для Jenkins (`10Gi`) та об'єкти `Application` в Argo CD залишаються недоторканими, а застосунок у `wagtail` разом із HPA продовжує штатно працювати.
- **Актуальний токен Amazon ECR (`start`):** оскільки пароль доступу до ECR діє 12 годин, під час старту скрипт знімає паузу з `cronjob/ecr-token-refresh` і одразу створює одноразову `Job` для його негайного оновлення.
- **Робота з Cluster Autoscaler:** зупинка CI/CD звільняє 6–7 слотів під поди, завдяки чому автоскейлер приблизно через 10 хвилин може прибрати незавантажену ноду `t3.small`. Під час запуску скрипт закладає таймаут очікування `300s`, щоб Cluster Autoscaler за потреби встиг підняти новий вузол.

## Спостереження за Cluster Autoscaler

Щоб відстежувати реакцію кластера на запуск або зупинку CI/CD у реальному часі, використовуйте логи контролера, його статусний `ConfigMap` та моніторинг нод:

```bash
# 1. Логи рішень Cluster Autoscaler у реальному часі
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler -f

# 2. Зведений стан групи вузлів, межі min/max та кандидати на видалення
kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml

# 3. Відстеження появи або видалення EC2-вузлів у кластері
kubectl get nodes -w
```

### На що звертати увагу

- **Розширення кластера (`Scale-Up`):** якщо після запуску `./scripts/cicd.sh start` новим подам бракує слотів (11 подів на `t3.small`) або RAM і вони переходять у статус `Pending`, у логах з'явиться рядок `Scale-up: setting group eks-general-... size to X`. Поява нового EC2-вузла та його перехід у статус `Ready` займає 2–4 хвилини.
- **Очікування перед зменшенням (`Scale-Down`):** після зупинки CI/CD або спаду навантаження автоскейлер перевіряє кожну ноду на можливість безпечного звільнення (`Simulating node removal` → `Node may be removed`). Вузли зі stateful-подами на EBS (`jenkins`, `prometheus`, `grafana`) не чіпаються, а для порожніх нод запускається таймер `Node is unneeded ... duration="..."`.
- **Видалення зайвої ноди:** щойно таймер простою досягне налаштованого порогу (`10m`), у логах з'явиться `Scale-down: removing node ...` (за умови, що поточна кількість нод більша за `minSize` у `cluster-autoscaler-status`), після чого системні поди переїдуть на інші вузли, а EC2-інстанс буде зупинено.

# Керування dev і staging (`dev-staging.sh`)

Скрипт зупиняє і знову запускає застосунки в `wagtail-dev` і `wagtail-staging`. Продакшн у `wagtail` не змінюється. Ingress, сертифікати, секрети і бази лишаються на місці: зупинка лише прибирає поди.

Просте `kubectl scale --replicas=0` Argo CD одразу поверне назад, бо в Application увімкнені `selfHeal` і `replicas: 1`. Тому `stop` записує Helm-параметр `replicaCount=0` в Application, а `start` цей параметр знімає, і чарт знову дає одну репліку.

```bash
chmod +x scripts/dev-staging.sh
./scripts/dev-staging.sh stop
./scripts/dev-staging.sh stop dev
./scripts/dev-staging.sh start staging
./scripts/dev-staging.sh status
```

| Команда | Опис |
| :--- | :--- |
| `stop` | Масштабує dev і staging до 0 реплік. |
| `stop dev` / `stop staging` | Зупиняє лише одне оточення. |
| `start` | Повертає одну репліку для dev і staging. |
| `start dev` / `start staging` | Запускає лише одне оточення. |
| `status` | Показує Deployment продакшну, dev і staging і чи стоїть override `replicaCount`. |
