# Argo Rollouts

## [Install](https://argoproj.github.io/argo-rollouts/installation/)

```bash
# with helm
helm upgrade -i argo-rollouts argo/argo-rollouts \
  -n argocd --create-namespace \
  --version 2.40.9 \
  -f k8s/helm/values.yaml

# with kustomize
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/download/v1.7.2/install.yaml
# or all-in-one
kubectl apply -k k8s/kustomize

# check if cli installed, if not install with asdf
# bash conpletion file /depo/tools/linux/kubectl_complete-argo-rollouts
kubectl argo rollouts version
```

To monitor from dashboard if not installed with ingress

```bash
kubectl argo rollouts dashboard
```

Open [http://127.0.0.1:3100/](http://127.0.0.1:3100/)

Syntax

```yaml
apiVersion: apps/v1
kind: Rollout
...
spec:
  ... # same as Deployment
  strategy:
    type:  <RollingUpdate, Recreate, blueGreen, canary> # This part support many strategy, despite native support only RollingUpdate & Recreate
    ...
  ...
```

## Deployment strategy

### Native strategies

```bash
kubectl create -n argocd secret generic dockerhub-credentials --from-literal=creds=alyvusal:$(cat ~/Documents/dockerhub_lab.token)

kubectl create ns prod
kubectl create ns staging

# deploy native k8s strategy
kubectl apply -k examples/native-deployment
# check node pprts 30000 and 30100, you will see same app version

kubectl delete -k examples/native-deployment
```

### BlueGreen

See [how-to](https://kubernetes-tutorial.schoolofdevops.com/argo_rollout_blue_green/)

```bash
kubectl apply -k examples/rollout-bluegreen/v1
kubectl argo rollouts list rollouts -n default
kubectl argo rollouts get rollout demo-app -n default
kubectl argo rollouts status demo-app -n default
```

Now deploy v2 and v3 and check from CLI and UI

```bash
kubectl apply -k examples/rollout-bluegreen/v2
kubectl apply -k examples/rollout-bluegreen/v3
```

### Canary

```bash
kubectl apply -k examples/rollout-canary/v1
kubectl apply -k examples/rollout-canary/v2
kubectl apply -k examples/rollout-canary/v3
kubectl argo rollouts get rollout demo-app -n prod
```

## Traffic Routing

### Ingress

```bash
kubectl apply -k examples/rollout-ingress-nginx/v1
kubectl apply -k examples/rollout-ingress-nginx/v2
kubectl apply -k examples/rollout-ingress-nginx/v3

# check http://demo-app-192.168.0.100.nip.io

# we create only demo-app canary but demo-app-demo-app-canary also created
kubectl -n prod get ingress

# see annotations
# https://kubernetes.github.io/ingress-nginx/examples/canary/
# Annotations:                 nginx.ingress.kubernetes.io/canary: true
#                              nginx.ingress.kubernetes.io/canary-weight: 0
# 0weight will increase: 0 > 20 > 40 > 60 > 80 > 100
kubectl describe ing demo-app-demo-app-canary -n prod
kubectl argo rollouts get rollout demo-app -n prod
```

### Experiment and Analysis

[Sample](https://kubernetes-tutorial.schoolofdevops.com/argo_experiments_analysis/)

rollout analysis and experiment

beside aanary replicaset, for experiment another single canary replicaset also created and experiment does on that, if succeded then changes weight for canary ingress

For test analysis connect directly to newly created canary rs pod's rs, not to pods created for users

[ref](https://kubernetes-tutorial.schoolofdevops.com/argo_experiments_analysis/)

```bash
kubectl apply -k examples/experiment-analysis/v1
kubectl apply -k examples/experiment-analysis/v2  # may hang on this, because there is no old data for v1
kubectl get AnalysisRun
kubectl apply -k examples/experiment-analysis/v3

kubectl get rs,svc,ep,ingress && kubectl describe ingress demo-app-demo-app-canary
```

[observe pod ui](http://demo-app-192.168.0.100.nip.io)

#### Explanation

Rollout Configuration:

- The rollout strategy includes canary steps with set weights and pauses.
- Each canary step includes an experiment with a specified duration (e.g., 3 minutes).
- The experiment step runs a experimental replicaset and launches a fitness test to validate if the new version looks okay.
- After 60% traffic is shifted to canary, a load test is lauched along with analysis from prometheus to check if the new version will perform okay with the load.

Analysis Templates:

- Defines a templates for running various tests and analyses.
- The loadtest container runs the load testing script against the canary service (vote-preview).
- The fitness-test job runs a test to validate if the new version is fit for deployment.
- the latency analysis fetches latency metrics from Prometheus and checks if the application is responding in acceptable time frame even with load conditions.

How it Works

- At each setWeight step, traffic is gradually shifted to the canary version.
- The analysis step includes both the load test and the metric analysis.
- The experiment runs for 3 minutes, during which the fitness test is conducted.
- Simultaneously with load test , the analysis template checks Prometheus metrics to ensure the canary is performing correctly.
- If the analysis detects errors beyond the acceptable threshold, the rollout will trigger a rollback.
- If the canary passes the load test and analysis, the rollout proceeds to the next step.
- By configuring the experiment and analysis to run in parallel, you can ensure comprehensive testing and validation of the canary version, enabling automatic rollback if any issues are detected.

## Load test

```bash
# k6 run --vus 10 --duration 30s k6.js
k6 run k6.js
```

**GitOps OutofSync Issue:**
The fact that Argo Rollout Controller will change the weight in the Virtual Service to the setWeight that was configured, creates an issue for GitOps users. Because this change affects the Live Manifest but not the Desired Manifest — the manifest in the git repository, OutofSync Issue will be prompted by ArgoCD.

In order to fix that add the following to ArgoCD Application.

Similar could be added to ArgoCD Application for image tag etc or disable self healing and pruning for rollouts.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <APP_NAME>
  namespace: argo
spec:
  ignoreDifferences:
    - group: networking.istio.io
      kind: VirtualService
      jqPathExpressions:
      - .spec.http[] | select(.name == "canary") | .route[0].weight
      - .spec.http[] | select(.name == "canary") | .route[1].weight

    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      jqPathExpressions:
        - .spec
        - .status
        - .metadata.annotations
```

 ArgoCD shows the application as "Progressing" until the rollout completes.

```yaml
# In argocd-cm ConfigMap
data:
  # Tell ArgoCD not to diff on rollout status fields
  resource.customizations.health.argoproj.io_Rollout: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase == "Healthy" then
        hs.status = "Healthy"
        hs.message = "Rollout is healthy"
      elseif obj.status.phase == "Paused" then
        hs.status = "Suspended"
        hs.message = "Rollout is paused"
      elseif obj.status.phase == "Degraded" then
        hs.status = "Degraded"
        hs.message = "Rollout is degraded"
      else
        hs.status = "Progressing"
        hs.message = "Rollout is progressing"
      end
    end
    return hs
```

With the `argo-cd` Helm chart, put the same keys under `configs.cm` (they become `argocd-cm` `data` entries). Example including cluster-wide Istio diff ignore (see `cd/k8s/helm/values.yaml`):

```yaml
configs:
  cm:
    resource.customizations.health.argoproj.io_Rollout: |
      hs = {}
      if obj.status ~= nil then
        if obj.status.phase == "Healthy" then
          hs.status = "Healthy"
          hs.message = "Rollout is healthy"
        elseif obj.status.phase == "Paused" then
          hs.status = "Suspended"
          hs.message = "Rollout is paused"
        elseif obj.status.phase == "Degraded" then
          hs.status = "Degraded"
          hs.message = "Rollout is degraded"
        else
          hs.status = "Progressing"
          hs.message = "Rollout is progressing"
        end
      end
      return hs
    resource.customizations.ignoreDifferences.networking.istio.io_VirtualService: |
      jqPathExpressions:
      - .spec.http[] | select(.name == "canary") | .route[0].weight
      - .spec.http[] | select(.name == "canary") | .route[1].weight
```

For **nginx Ingress** canary annotations, use `spec.ignoreDifferences` on the Application (or a matching `resource.customizations.ignoreDifferences.networking.k8s.io_Ingress` block with the jq paths or `managedFieldsManagers` you need); there is no single global pattern because annotation keys differ by setup.

The **CRD** `ignoreDifferences` block above is very broad (hides almost all CRD drift); only use it if you understand the tradeoff, not as a default for Rollouts.

[ref](https://medium.com/israeli-tech-radar/deployment-strategies-argo-rollouts-1980fc0685e6) and [ref](https://oneuptime.com/blog/post/2026-02-26-argocd-argo-rollouts-progressive-delivery/view#argocd-sync-behavior-with-rollouts)

## REFERENCE

- [Rollouts Spec](https://argoproj.github.io/argo-rollouts/features/specification/)
- [argo_rollout_blue_green](https://kubernetes-tutorial.schoolofdevops.com/argo_rollout_blue_green/)
- [rollouts-demo](https://github.com/argoproj/rollouts-demo)
- [argo-rollouts](https://github.com/argoproj/argo-rollouts/tree/master/examples)
- [Dashboard](https://github.com/argoproj/argo-rollouts/blob/master/examples/dashboard.json)
- [rollouts-demo Examples](https://github.com/argoproj/rollouts-demo/tree/master/examples)
