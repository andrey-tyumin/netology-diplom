### Дипломный проект курса DevOps netology.ru.  
Все файлы, нужные для выполнения работы залиты в этот репозиторий, ссылки в тексте не пишу, т.к. их очень много.  
В файлах удалены ключи, токены и т.д.   
#### 1. Создание облачной инфраструктуры  
 ##### 1.1  Подготовка к развороту инфраструктуры.   
Сделал предварительный терраформ проект для разворачивания docker registry, bucket(и kms ключ для шифрования)   
и serviceaccount,ключи для него, даем ему права с помощью terraform.  
Процесс:  
В каталоге terraform_bucket делаем:  
```
terraform init  
terraform plan
terraform apply
```
После завершения нам нужны следующие данные о созданных ресурсах:  
"access_key"  
"secret_key"  
"service_account_id"  
и файл sa-diplom-key.json -авторизированный ключ servicaccount-а  
получим данные из tfstate все сразу:  
```
terraform state pull | jq '.resources[] | select(.type == "yandex_iam_service_account_static_access_key") | .instances[0].attributes'  
```
или раздельно:  
```
terraform state pull | jq -r '.resources[] | select(.type == "yandex_iam_service_account_static_access_key") | .instances[0].attributes.access_key'
terraform state pull | jq -r '.resources[] | select(.type == "yandex_iam_service_account_static_access_key") | .instances[0].attributes.secret_key'
terraform state pull | jq -r '.resources[] | select(.type == "yandex_iam_service_account_static_access_key") | .instances[0].attributes.service_account_id'
```
Экспортируем serviceaccount id в переменные окружения (для второго этапа разворота инфраструктуры):  
```
export TF_VAR_SADIPLOMID=`terraform state pull | jq -r '.resources[] | select(.type == "yandex_iam_service_account_static_access_key") | .instances[0].attributes.service_account_id'`
```
access_key и secret_key  в качестве переменных terraform в main.tf не принимает, так что нужно будет заносить руками.  
Чтобы частично ускорить процесс, сделал скрипт get_res.sh.  Он показывает все нужные данные и копирует файл с ключём в каталог, где терраформом разворачиваем инфраструктуру.  

 ##### 1.2 Разворот инфраструктуры.  
В каталоге terraform:  
```
terraform init
```
Сделаем workspaces:  
```
terraform workspace new prod
terraform workspace new stage
```
Проверим:  
```
terraform workspace list
```
Дальше делал в prod workspace:  
```
terraform workspace select prod
```
В каталоге terraform, в main.tf, в раздел backend "s3" записываем access_key и secret_key сервисаккаунта.  
После делаем:  
```
terraform init
terraform plan
terraform apply
```
Описание разворачивающегося:  
tfstate в S3 backend, vpc, три subnet в разных зонах доступа, 4 вм под ноды, 1 вм - под control plane, 1 вм - под ингресс контроллеры, 1 вм - под гитлаб, 
 для вм использую образ ubuntu 20.04.  

В зависимости от workspace будут изменены параметры:   
Путь в бакете, куда будет сохранен tfstate(это автоматически),  
количество вм в инстансе груп(prod -4, stage -2), 
образ разворачиваемый в инстансе(prod - ubuntu 20.04, stage - ubuntu 18.04),  
так же файл для генерации инвентори для kubespray.  
Добавляю обычно адрес control plane в переменную окружения(для удобства настройки кластера, после настройки удаляю):  
``
export cp=51.250.69.139  
``

#### 2. Разворот K8s.  
Делал с помощью kubespray.  
Клонируем репозиторий:  
```
git clone https://github.com/kubernetes-sigs/kubespray.git
```
Копируем sample(пример конфигурации) в diplomcluster(тут буду делать свою конфигурацию):  
```
cp -r kubespray/inventory/sample/ kubespray/inventory/diplomcluster
```
Копируем инвентори, сгенерированный терраформом в каталог своей конфигурации:  
```
cp ../terraform/inventory-prod.ini kubespray/inventory/diplomcluster/
```
Добавим в сертификат внешний ip адрес control plane(берем из output терраформа или в консоли ЯОблака):  
```
sed -i '/# supplementary_addresses_in_ssl_keys:*/a supplementary_addresses_in_ssl_keys: ['$cp']' kubespray/inventory/diplomcluster/group_vars/k8s_cluster/k8s-cluster.yml
```
для разворота Ingress controller в /kubespray/inventory/diplomcluster/group_vars/k8s-cluster/addons.yml  
 поставим\поменяем эти опции:  
```
ingress_nginx_enabled: true
ingress_publish_status_address: ""
ingress_nginx_nodeselector:
   node-role.kubernetes.io/ingress: "true"
ingress_nginx_tolerations:
   - key: "node-role.kubernetes.io/ingress"
     operator: "Exists"
ingress_nginx_insecure_port: 80
ingress_nginx_secure_port: 443
ingress_nginx_configmap:
  server-tokens: "False"
  proxy-body-size: "2048M"
  proxy-buffer-size: "16k"
  worker-shutdown-timeout: "180"
```
Для того, чтобы контроллер развернулся на нужной вм, создаем файл   
/kubespray/inventory/diplomcluster/group_vars/kube-ingress.yml, и запишем туда:  
```
node_labels:
  node-role.kubernetes.io/ingress: "true"
node_taints:
  - "node-role.kubernetes.io/ingress=:NoSchedule"
```
Запускаем:   
```
ansible-playbook -i inventory/diplomcluster/inventory-prod.ini -u andrey cluster.yml -b -v
```
После завершения получаем конфиг кластера:  
```
ssh andrey@$cp sudo chown -R andrey:andrey /etc/kubernetes/admin.conf
scp andrey@$cp:/etc/kubernetes/admin.conf kubespray-do.conf
```
Прописываем внешний адрес кластера в скачанном файле конфига:  
```
sed -i 's/127.0.0.1:6443/'$cp':6443/' kubespray-do.conf
```
Прописываем путь к конфигу в переменную окружения:  
```
export KUBECONFIG=$PWD/kubespray-do.conf
```
Удалим переменную окружения:
```
unset cp
```

Проверяем:  
```
kubectl get pods -A
kubectl get nodes
```

#### 3. Создание Docker образа.  
В качестве приложения использую простейший Python\Flask скрипт.  
слушает на 5000 порту.  
Dockerfile:  
```
FROM python:3.9.13-slim-bullseye
RUN mkdir /opt/flaskService
COPY flaskService.py /opt/flaskService/
COPY requirements.txt /opt/flaskService/
WORKDIR /opt/flaskService
RUN pip install -r requirements.txt
EXPOSE 5000
CMD [ "python", "flaskService.py" ]
```
Скрипт:  
```
# flaskService.py
from flask import Flask
application = Flask(__name__)

@application.route("/")
def hello():
    return "<h1 style='color:blue'>Hello! It's Python\Flask server!</h1>"

if __name__ == "__main__":
    application.run(host='0.0.0.0')
```
requirements.txt:  
```
click==8.1.3
Flask==2.1.2
importlib-metadata==4.11.4
itsdangerous==2.1.2
Jinja2==3.1.2
MarkupSafe==2.1.1
Werkzeug==2.1.2
zipp==3.8.0
```
Загружаем образ в режистри ЯОблака:  
Для загрузки в яндекс режистри образу нужно присвоить определенный тэг  
такого вида: cr.yandex/<ID реестра>/<имя Docker-образа>:<тег>  
Ставим тэг:  
```
docker tag flask4 cr.yandex/crp24405qdf48unu20bv/python-flask:v0.1
```
Авторизуемся в режистри из-под сервисного аккаунта, используя сгенерированный ранее терраформом json:  
```
cat sa-diplom-key.json | docker login --username json_key --password-stdin cr.yandex
```
Потом загружаем образ:  
```
docker push cr.yandex/crp24405qdf48unu20bv/python-flask:v0.1
```

#### 4. Подготовка cистемы мониторинга и деплой приложения.  
Ингресс контролер в кластер уже установлен, при развороте k8s kubespray-ем. Для приложения сделаем деплой, сервис приложения, и ингресс на этот сервис.  
Ингресс контроллер устанавливается на отдельную ноду в режиме NodePort  (больше на эту ноду ничего не ставится, кроме служебных подов).  

Деплой с помощью helm, т.к. больше распространен, по нему больше информации.  
Манифесты для деплоя приложения без helm-а прилагаются.  
Приложение будет доступно на 80 порту вм с ингресс контроллером.  
Чарт с приложением прилагается (каталог bruce).  
Делаем:  
```
helm install cool ./bruce
```
Чарт разворачивает Deployment, service, ingress.  
После можно проверить зайдя на внешний адрес вм с ингрессом.  

Для установки prometheus, grafana, alertmanager, node_exporter используется   
рекомендованный в задании пакет kube-prometheus, helm чарт для него:   
kube-prometheus-stack (https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)  
Делаем:  
```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install mon prometheus-community/kube-prometheus-stack
```
Графана в subpath плоховато работала(совсем, совсем), поэтому решил задеплоить  для доступа к ней еще один  
ingress controller(но с портами на хосте 81 и 444) на ту же ноду, где установлен первый ингресс контроллер.  
Сделал:  
```
helm install ingress-nginx-2 ingress-nginx/ingress-nginx  --namespace ingress-nginx -f ./gr_ingress_values.yaml
```
Содержание gr_ingress_values.yaml:  
```
controller:
  ingressClassResource:
    name: nginx-grafana
    controllerValue: stop.me.please/ingress-nginx-2
    enabled: true
    ingressClassByName: true
  hostPort:
    enabled: true
    ports:
      http: 81
      https: 444
  nodeSelector:
    node-role.kubernetes.io/ingress: "true"
  tolerations: 
    - key: node-role.kubernetes.io/ingress
      operator: Exists
      effect: NoSchedule
```
Создаем ingress для grafana с указанием нужного ingressClass(файл ingress_grafana.yaml):  
```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
spec:
  ingressClassName: nginx-grafana
  defaultBackend:
    service:
      name: mon-grafana
      port:
        number: 80
```
Применим:   
```
kubectl apply -f ./ingress_grafana.yaml
```
После можно зайти, проверить по тому же адресу(внешний адрес вм с ингресс), но на порту 81.  
Логин по умолчанию: admin, пароль: prom-operator, сразу меняем и записываем.  
Дашборду свою не делал, импортировал хорошую(мне понравилась) готовую: (https://grafana.com/grafana/dashboards/15759)  


#### 5. Установка и настройка CI/CD  
Использовал Gitlab инстанс в ЯОблаке(разворачивается terraform-ом)  
Заходим по внешнему IP вм с gitlab. Под root, пароль смотрим на вм gitlab в /etc/gitlab/initial_root_password.  
Записываем\сохраняем пароль куда-нить(или меняем, потом записываем).  

Заходим, создаем проект, копируем в репозиторий файлы для сборки докер образа:  
```
Dockerfile
requirements.txt
flaskService.py
```
создаем сервисный аккаунт в кластере(нужен для разворота helm чарта из gitlab):  
```
kubectl apply -f gitlab-admin-service-account.yaml
```
Содержание файла gitlab-admin-service-account.yaml:   
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitlab-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gitlab-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: gitlab-admin
  namespace: kube-system
```
Получим токен аккаунта:  
```
kubectl -n kube-system get secrets -o json | \
jq -r '.items[] | select(.metadata.name | startswith("gitlab-admin")) | .data.token' | \
base64 --decode
```
Запишем\сохраним.  

Gitlab Runner запускаем в кластере.  
Добавляем repo с чартом:  
```
helm repo add gitlab https://charts.gitlab.io
```
В проекте идем в:  
```
Setting - CI/CD - Runners - Expand.
```
Смотрим на URL и registration token. Сохраняем\записываем.  

Правим values-gitlab-runners.yaml для установки чарта(ставим записанные gitlabUrl и runnerRegistrationToken - их получили ранее):  
```
imagePullPolicy: IfNotPresent
gitlabUrl: http://51.250.84.4/
runnerRegistrationToken: "here_you_need_runner_registration_token"
terminationGracePeriodSeconds: 3600
concurrent: 10
checkInterval: 30
sessionServer:
 enabled: false
rbac:
  create: true
  clusterWideAccess: true
  podSecurityPolicy:
    enabled: false
    resourceNames:
      - gitlab-runner
runners:
  config: |
    [[runners]]
      [runners.kubernetes]
        namespace = "{{.Release.Namespace}}"
        image = "ubuntu:20.04"
        privileged = true
```

Устанавливаем чарт:  
```
helm install --namespace default gitlab-runner -f values-gitlab-runners.yaml gitlab/gitlab-runner
```
проверяем под:  
```
kubectl get pods -n default | grep gitlab-runner
```
Добавляем переменные в gitlab для доступа к кластеру и выгрузки образов в яндекс режистри.  
Идем в Settings - CI/CD - Variables - Expand.  
Нужно будет добавить:   
KUBE_URL - адрес мастера (получим в выводе "kubectl cluster-info")  
KUBE_TOKEN - токен сервисной учетки, полученный раньше.  
Для доступа к яндекс режистри:  
YC_OAUTH_TOKEN - токен(свой или сервисной учетки в Яндекс облаке) для загрузки образа в яндекс режистри.  
Для загрузки\выгрузки helm чартов:  
GITLAB_ACCESS_TOKEN - это personal access token для загрузки helm чарта в gitlab package registry, его нужно создать отдельно:  
Идем в настройки профиля User Settings - Access Tokens.  
Вводим имя, дату, до которой токен работает, области действия, и жмем создать токен.  
Записываем\Сохраняем токен, создаем переменную с его значением.  
GITLAB_PROJECT_ACCESS - токен для доступа к проекту, создавал для доступа к созданному в gitlab helm repo(иначе чарт не подгружался в pipeline -е),   
наверное можно было бы обоитись только им, без personal access token, но я не стал проверять и менять .gitlab-ci.yml. Создается в  
проекте: Settings-Access   tokens, дальше аналогично пред. токену. Записываем\Сохраняем этот токен тоже, создаем переменную с его значением.  
Название переменных роли не играют.  

Сделам helm registry на gitlab-е.  
Создаем helm package и загружаем его в Gitlab Package Registry:  
```
helm package ./bruce
```
Загрузим chart package в package registry:  
```
curl --request POST \
     --form 'chart=@bruce-0.1.0.tgz' \
     --user root:here_you_need_gitlab_personal_access_token \
     http://51.250.84.4/api/v4/projects/2/packages/helm/api/stable/charts
```
Тут по ситуации менять: сам чарт package, user, token, и путь до режистри(и в нем id проекта, тут id проекта: 2).  

Создаем .gitlab-ci.yml:  
```
stages:
  - build
  - deploy

build:
  stage: build
  variables:
    DOCKER_DRIVER: overlay2
    DOCKER_TLS_CERTDIR: ""
    DOCKER_HOST: tcp://localhost:2375/
#  image: cr.yandex/yc/docker-helper:0.2
  image: docker:latest
  services:
    - docker:19.03.1-dind
  script:
    - docker login --username oauth --password $YC_OAUTH_TOKEN cr.yandex
    - docker build . -t cr.yandex/crp24405qdf48unu20bv/python-flask:$CI_COMMIT_MESSAGE
    - docker push cr.yandex/crp24405qdf48unu20bv/python-flask:$CI_COMMIT_MESSAGE

deploy:
  image: gcr.io/cloud-builders/kubectl:latest
  stage: deploy
  script:
      - kubectl config set-cluster k8s --server="$KUBE_URL" --insecure-skip-tls-verify=true
      - kubectl config set-credentials admin --token="$KUBE_TOKEN"
      - kubectl config set-context default --cluster=k8s --user=admin
      - kubectl config use-context default
      - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      - helm repo add --username root --password $GITLAB_PROJECT_TOKEN bruce http://51.250.84.4/api/v4/projects/2/packages/helm/stable
      - helm repo update
      - helm upgrade --install cool bruce/bruce --set image.tag=$CI_COMMIT_MESSAGE
      - helm repo list
  rules:
    - if: $CI_COMMIT_MESSAGE=="v1.0.0"

```
Тэг на образ проставляется из commit message.  
По заданию, если тег=v.1.0.0, кроме деплоя образа в режистри, образ деплоится(обновляется) в кластер.  
