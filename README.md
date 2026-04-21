# Argo CD, Argo Workflows, Argo Rollouts, Argo Events, Image Updater, Autopilot

all-in-one lab guide

## Prepare environment

install bases

```bash
# prometheus
helm upgrade -i prom -n monitoring \
  prometheus-community/kube-prometheus-stack \
  --create-namespace \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30400 \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# install ingress-nginx with your preferred values and append enable metrics
helm upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --reuse-values --set controller.metrics.serviceMonitor.enabled=true
```

install argo bundle

```bash
# argocd
helm upgrade -i argocd argo/argo-cd -n argocd --create-namespace --version 9.5.1 -f cd/k8s/helm/values.yaml

# argocd image updater
helm upgrade -i argocd-image-updater argo/argocd-image-updater -n argocd --create-namespace \
  --version 1.1.5 -f image-updater/k8s/helm/values.yaml

# argo rollouts
helm upgrade -i argo-rollouts argo/argo-rollouts -n argocd --create-namespace \
  --version 2.40.9 -f rollouts/k8s/helm/values.yaml

# argo workflow
kubectl apply -k workflows/k8s/kustomize

# argo events
kubectl apply -k events/k8s/kustomize
```

logins

```bash
# argocd
argocd login --insecure --grpc-web argocd-192.168.0.100.nip.io --username admin --password admin

# argocd image updater
# use below command when argocd endpoint used in config
# TOKEN=$(argocd account generate-token --account image-updater --id image-updater --grpc-web)
# kubectl create secret generic argocd-image-updater-secret \
#   --from-literal argocd.token=$TOKEN --dry-run=client -o yaml | kubectl -n argocd apply -f -
# kubectl -n argocd rollout restart deployment argocd-server

# argo workflows
export ARGO_TOKEN="Bearer $(kubectl -n argo create token argo-admin --duration 24h)"  # UI + CLI
export ARGO_SERVER='argo-192.168.0.100.nip.io:443'
export ARGO_HTTP1=true
export ARGO_SECURE=true
export ARGO_INSECURE_SKIP_VERIFY=true  # for custom certs
export ARGO_NAMESPACE=argo

# grafana
kubectl -n monitoring get secret prom-grafana -o json | jq -r '.data."admin-user"' | base64 -d
kubectl -n monitoring get secret prom-grafana -o json | jq -r '.data."admin-password"' | base64 -d
# import dashboard from content of https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/grafana/dashboards/nginx.json
```

UI:

- [ArgoCD](https://argocd-192.168.0.100.nip.io)
- [Argo Rollouts](http://argo-rollouts-192.168.0.100.nip.io)
- [Argo Workflows](https://argo-192.168.0.100.nip.io)
- [Grafana UI](http://172.18.0.4:30400/login)

### Tokens

#### Github

Create fine-grained token with Read/Write on Contents (token: github_pat_TOKEN-xxxx) and write to ~/Documents/github_lab.token

Allow to sre (for image updater to commit last image tag) and demo-app repos

```bash
# argocd
kubectl -n argocd create secret generic github-token-secret --from-literal=username=alyvusal --from-literal=password=$(cat ~/Documents/github_lab.token)

# argo-events
kubectl -n argo-events create secret generic github-token-secret --from-literal=username=alyvusal --from-literal=password=$(cat ~/Documents/github_lab.token)

# argo workflows
kubectl -n argo create secret generic github-token-secret --from-literal=username=alyvusal --from-literal=password=$(cat ~/Documents/github_lab.token)
```

#### Dockerhub

Create personal token for dockerhub (token: dckr_pat_TOKEN-xxxx) and write to ~/Documents/dockerhub_lab.token

```bash
# argocd
kubectl -n argocd create secret docker-registry docker-registry-creds --docker-server=https://index.docker.io/v1/ \
   --docker-username=alyvusal --docker-password=$(cat ~/Documents/dockerhub_lab.token)

# image updater
kubectl create -n argocd secret generic dockerhub-credentials --from-literal=creds=alyvusal:$(cat ~/Documents/dockerhub_lab.token)

# argo workflows
kubectl -n argo create secret docker-registry docker-registry-creds --docker-server=https://index.docker.io/v1/ \
   --docker-username=alyvusal --docker-password=$(cat ~/Documents/dockerhub_lab.token)

# argo-events
kubectl -n argo-events create secret docker-registry docker-registry-creds --docker-server=https://index.docker.io/v1/ \
   --docker-username=alyvusal --docker-password=$(cat ~/Documents/dockerhub_lab.token)

# demo-app in default ns
kubectl create secret docker-registry docker-registry-creds --docker-server=https://index.docker.io/v1/ \
   --docker-username=alyvusal --docker-password=$(cat ~/Documents/dockerhub_lab.token)

# trivy
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/trivy-operator/v0.3.0/deploy/static/trivy-operator.yaml
```

## Application

```bash
# argo events
kubectl -n argo-events apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/rbac/sensor-rbac.yaml
kubectl -n argo-events apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/rbac/workflow-rbac.yaml
kubectl -n argo-events apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml
# works with trigger
kubectl apply -f workflows/examples/WorkflowTemplate/argo-bundle-lab/demo-app-template.yaml
kubectl apply -f events/examples/argo-bundle-lab/webook-eventsource.yaml
kubectl apply -f events/examples/argo-bundle-lab/polling-sensor.yaml
kubectl apply -f events/examples/argo-bundle-lab/poller-cronjob.yaml

# argo workflow standalone workflow
argo submit -n argo workflows/examples/Workflow/argo-bundle-helm/lab/workflow.yaml \
  -p repo-url=https://github.com/alyvusal/demo-app.git \
  -p branch=main \
  -p image=alyvusal/demo-app \
  -p dockerfile=Dockerfile

# argocd
# argocd repo add https://github.com/alyvusal/sre.git --username alyvusal --password $(cat ~/Documents/github_lab.token)
kubectl -n argocd create secret generic repo-flamingo --from-literal username=alyvusal --from-literal password=$(cat ~/Documents/github_lab.token) \
  --from-literal type=git --from-literal url=https://github.com/alyvusal/flamingo.git --dry-run=client -o yaml | kubectl label -f - argocd.argoproj.io/secret-type=repository
kubectl apply -f cd/examples/app-of-apps/root.yaml
```

rollout analysis and experiment

[ref](https://kubernetes-tutorial.schoolofdevops.com/argo_experiments_analysis/)

```bash
# change version on app-of-apps
kubectl apply -k rollouts/examples/experiment-analysis/v1
# for v2 may hang, because there is no old data for v1
kubectl get AnalysisRun

kubectl describe ingress demo-app && kubectl describe ingress demo-app-demo-app-canary && kubectl get rs,svc,ep,ingress
```

[observe pod ui](http://demo-app-192.168.0.100.nip.io)
