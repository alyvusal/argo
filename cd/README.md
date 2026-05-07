# ArgoCD

[back](../README.md)

## Setup

- [Installation](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Login to server](https://argo-cd.readthedocs.io/en/stable/getting_started/#4-login-using-the-cli)
- [Create An Application](https://argo-cd.readthedocs.io/en/stable/getting_started/#6-create-an-application-from-a-git-repository)

Installation

```bash
# with helm
helm upgrade -i argocd argo/argo-cd -n argocd --create-namespace --version 9.5.12 -f k8s/helm/values.yaml

# with kustomize
kubectl apply -k k8s/kustomize

# github token when PRs are used
kubectl -n argocd create secret generic github-token \
  --from-literal=token=$GITHUB_TOKEN_ORG \
  --dry-run=client -o yaml | kubectl apply -f -
```

Get initial password for `admin` user

```bash
argocd admin initial-password -n argocd
# or
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
# or set your own
./reset-argo-password.sh admin  # set argocd password to admin
```

Login (use `--insecure` if custom certificate used in url)

```bash
# with port forwarding
argocd login --insecure --grpc-web 127.0.0.1:8080 --username admin --password admin

# with ingress
argocd login --insecure --grpc-web localhost --username admin --password admin  # kind cluster only
argocd login --insecure --grpc-web argocd-192.168.0.100.nip.io --username admin --password admin

# sso
argocd login --sso argocd-192.168.0.100.nip.io
```

Dashboard with local cli

```bash
argocd admin dashboard -n argocd [--port 8080]
```

check permissions

```bash
kubectl --as system:serviceaccount:argocd:argocd-application-controller auth can-i list pods -n argocd
kubectl --as system:serviceaccount:argocd:argocd-server auth can-i list pods -n argocd
kubectl --as system:serviceaccount:argocd:argocd-server auth can-i get pods -n argocd

argocd proj role create-token team ci-role -e 1d
```

### TL;DR

Recover cluster from [Autopilot](./autopilot/README.md#recover) for testing it with ingress ready in it.

## Application & ApplicationSet deployment

- [App yaml syntax](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications)

Values injections have the following order of precedence:

1. valueFiles
2. values
3. parameters

install [example Application](./examples/Application.yaml)

imperative way (App of Apps example)

```bash
# Application
argocd app create apps \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/argoproj/argocd-example-apps.git \
    --path apps

argocd app sync apps
```

declarative way

```bash
# Application
kubectl apply -f ./examples/disabled/Application.yaml
argocd app sync nginx
argocd app sync guestbook

# ApplicationSet
kubectl apply -f ./examples/disabled/ApplicationSet.yaml
argocd app sync guestbook-prod
argocd app sync guestbook-dev

# AppProject
kubectl apply -f examples/AppProject.yaml

argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-namespace default \
  --dest-name kind-dev \
  --grpc-web \
  --sync-policy=auto \
  --project=development \
  --upsert

argocd app delete argocd/guestbook --grpc-web --yes
# or
argocd app terminate-op argocd/guestbook --grpc-web
```

change image to see sync status

```bash
kubectl patch deployments.apps guestbook-ui -p '{"spec":{"template":{"spec":{"containers":[{"name":"guestbook-ui","image":"nginx:1.26-alpine-slim"}]}}}}'
```

to use [private docker registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)

```bash
kubectl create secret generic regcred --from-file=.dockerconfigjson=.docker/config.json --type=kubernetes.io/dockerconfigjson
```

and update spec in manifest

```yaml
...
spec:
  imagePullSecrets:
  - name: regcred
  containers:
  - name: guestbook-ui
    image: alyvusal/nginx
...
```

## Repo

```bash
# create secret to access gitlab repo
argocd repo add "https://...myapp.git" --username "aly.vusal@gmail.com"  --password glpat-<PERSONAL ACCESS TOKEN WITH api GRANTS>

# check created secret
kubectl get secrets -n argocd
```

### App directory structure in repo

```bash
mkdir -p apps/{app{1,2},common}/{test,dev,uat,prod}
tree apps

apps/
├── app1
│   ├── dev
│   ├── prod
│   ├── test
│   └── uat
├── app2
│   ├── dev
│   ├── prod
│   ├── test
│   └── uat
└── common
    ├── dev
    ├── prod
    ├── test
    └── uat
```

## [Argo Tools](https://github.com/argoproj-labs)

- [Argo CD Autopilot](./autopilot/README.md)
- [Argo CD Image Updater](./image-updater/README.md)

## CI

create token for CI

```bash
argocd account generate-token --account <USER>
```

## Backup

```bash
argocd admin export -n argocd > backup-$(date +"%Y-%m-%d_%H:%M").yml
argocd admin import < backup-2021-09-15_18:16.yml
```

## Monitoring

OOMKilled

```sql
sum by (pod, container, namespace) (kube_pod_container_
status_last_terminated_reason{reason="OOMKilled"}) *
on (pod,container) group_left sum by (pod, container)
(changes(kube_pod_container_status_restarts_total[5m])) > 0
```

Sync status

```sql
sum by (name) (changes(argocd_app_sync_total{phase="Failed",
exported_namespace="argocd", name=~"accounting.*"}[5m]))>0
```

app health

```sql
argocd_app_info{health_status="Degraded",exported_
namespace="argocd",name=~"prod.*",name!~".*app"}
```

## Notifications

- [Notifications](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/)
- [ArgoCD Notifications (Successful/Failed Deployments)](https://www.youtube.com/watch?v=OP6IRsNiB4w&list=PLiMWaCMwGJXkktZoHhmL6sbg7ELNjv9Xw&index=3)

```bash
kubectl create secret generic argocd-notifications-secret -n argocd \
  --from-literal=slack-webhook-url=https://hooks.slack.com/services/xxxx/yyy/zzz

# Install Triggers and Templates from the catalog
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml
```

## [User management](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)

```bash
argocd account update-password --account vusal
```

## Trigger Deployment

To trigger an Argo Workflow Template natively in Argo, you can use various methods, such as:

1. Manually Triggering with Argo CLI: You can trigger the workflow template by creating a workflow that references the template. This is done via the argo submit command. Example:

    ```bash
    argo submit -n <namespace> --from=workflowtemplate/<template-name>
    ```

2. Triggers from a GitHub or GitLab webhook: You can set up a webhook that triggers an Argo Workflow when changes are pushed to a repository or a specific branch. This could involve creating a custom trigger using Argo Events to listen for GitHub or GitLab webhook events and then submit a workflow based on these events.
3. Argo Events: Argo Events provides event-driven automation that can trigger workflows based on events from other systems, such as a message on a Kafka topic, HTTP events, or cron schedules. An event source listens for specific triggers (like HTTP requests, cron schedules, or messages in a queue), and then an Argo EventBus processes the event and triggers a workflow.

    Example of a trigger using Argo Events with an HTTP event:

    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: EventSource
    metadata:
      name: my-event-source
    spec:
      service:
        ports:
          - port: 80
            targetPort: 8080
            protocol: TCP
        routes:
          - name: http
            eventBusName: default
            eventSourceName: my-event-source
            eventType: my-event-type
            trigger:
              template:
                name: <workflow-template-name>
    ```

4. Cron Workflows: If you want to trigger the workflow template on a schedule, you can use Argo CronWorkflows, which allow you to define scheduled triggers for workflows, just like cron jobs. Example:

    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: CronWorkflow
    metadata:
      name: my-cron-workflow
    spec:
      schedule: "0 0 * * *"
      workflowSpec:
        templates:
        - name: <template-name>
    ```

5. API Trigger: You can trigger a workflow programmatically via the Argo API. You can send a POST request to the Argo server to start a workflow using your template.

    Example:

    ```bash
    curl -X POST -H "Content-Type: application/json" \
      -d '{"templateRef": {"name": "<template-name>"}}' \
      <argo-server-url>/api/v1/workflows
    ```

Which method fits best depends on your use case, such as whether you want a manual or automatic trigger, or if you need to integrate with external systems like Git or a messaging queue.

## REFERENCE

- [awesome-argo](https://github.com/akuity/awesome-argo)
- [killercoda labs](https://killercoda.com/explore?search=argo&type=profile)
