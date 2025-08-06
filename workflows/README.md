# Argo Workflows

[back](../README.md)

## [Install](https://argo-workflows.readthedocs.io/en/latest/installation/#installation-methods)

Full installation (UI, user access, namespace)

```bash
kubectl apply -k k8s/kustomize
```

or create namespace and install server components

```bash
# install server
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.6.2/install.yaml
```

- [Set Github credentials](../README.md#Github)
- [Set Dockerhub credentials](../README.md#dockerhub)

## [CLI and UI Access](https://argo-workflows.readthedocs.io/en/latest/security/#ui-access)

Export variables for CLI and UI access

```bash
# get token for argo-admin user and note for server access
# 2nd way to get token via secret: https://argo-workflows.readthedocs.io/en/release-3.5/access-token/#token-creation
export ARGO_TOKEN="Bearer $(kubectl -n argo create token argo-admin --duration 24h)" # expires by default in 1 hour
echo $ARGO_TOKEN # use output for UI access. Include whole line from "Bearer .."
export ARGO_SERVER='argo-192.168.0.100.nip.io:443'
export ARGO_HTTP1=true
export ARGO_SECURE=true
export ARGO_INSECURE_SKIP_VERIFY=true  # for custom certs
export ARGO_NAMESPACE=argo
# export ARGO_BASE_HREF=

# Test accesss
curl -s http://argo-192.168.0.100.nip.io/api/v1/info -H "Authorization: $ARGO_TOKEN" | jq
```

- [How-to: Access token](https://argo-workflows.readthedocs.io/en/release-3.5/access-token/#token-creation)
- [Argo Server SSO](https://argo-workflows.readthedocs.io/en/latest/argo-server-sso/)

[Access UI](http://argo-192.168.0.100.nip.io) with generated token

## Workflow

### [Workflow Pod Permissions](https://argo-workflows.readthedocs.io/en/latest/security/#workflow-pod-permissions)

Workflow pods run using either:

- The default service account.

  ```bash
  # allow create workflow in argo namespace, create similar one for other namespaces
  kubectl apply -f examples/extra/workflow-default-sa-permissions.yaml
  ```

- The service account declared in the workflow spec.

### Create Workflow

```bash
# use CLI
argo submit -n argo --watch examples/Workflow/argo-bundle-lab/workflow.yaml \
  -p repo-url=https://github.com/alyvusal/demo-app.git \
  -p branch=main \
  -p image=alyvusal/demo-app \
  -p dockerfile=Dockerfile

argo list  # it is same as: argo -n argo list
```

[`WorkflowTemplate` vs `template`](https://argo-workflows.readthedocs.io/en/latest/workflow-templates/#workflowtemplate-vs-template)

Template can be of type container, containerset, script, data, resource, dag, steps or suspend.
Can be referenced by an entrypoint or by other dag and step templates.

DAG and step templates also called template invocators.

### Create workflow via API

```bash
NS=default
curl -k \
   https://argo-192.168.0.100.nip.io/api/v1/workflows/$NS \
  -H "Authorization: $ARGO_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
  "workflow": {
    "metadata": {
      "generateName": "hello-world-"
    },
    "spec": {
      "templates": [
        {
          "name": "main",
          "container": {
            "image": "docker/whalesay",
            "command": [
              "cowsay"
            ],
            "args": [
              "hello world"
            ]
          }
        }
      ],
      "entrypoint": "main"
    }
  }
}'
```

## Webhooks

To keep things simple, we used the `api/v1/workflows` endpoint to create workflows, but there's one endpoint that is specifically designed to create workflows via an api: `api/v1/events`.

You should use this for most cases (including Jenkins):

- It only allows you to create workflows from a WorkflowTemplate , so is more secure.
- It allows you to parse the HTTP payload and use it as parameters.
- It allows you to integrate with other systems without you having to change those systems.
- Webhooks also support GitHub and GitLab, so you can trigger workflow from git actions.

To use this, you need to create a `WorkflowTemplate` and a `WorkflowEventBinding`:

A workflow event binding consists of:

- An event selector that matches events
- A reference to a WorkflowTemplates using workflowTemplateRef
- Optional parameters

Example:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowEventBinding
metadata:
  name: hello
spec:
  event:
    selector: payload.message != ""
  submit:
    workflowTemplateRef:
      name: hello
    arguments:
      parameters:
        - name: message
          valueFrom:
            event: payload.message
```

In the above example, if the event contained a message, then we'll submit the workflow template and the workflow will echo the message.

Create the WorkflowTemplates :

`kubectl apply -f examples/Workflow/features/event.yaml`

Create the workflow event binding:

'kubectl apply -f hello-workfloweventbinding.yaml'

Trigger workflow via webhook:

```bash
NS=default
curl http://argo-192.168.0.100.nip.io/api/v1/events/$NS/- -H "Authorization: $ARGO_TOKEN" -d '{"message": "hello events"}'`
```

You will not get a response - this is processed asynchronously.

Allow about 5 seconds for the workflow to start and then check the logs:

argo logs @latest

## REFERENCE

- [Home](https://argo-workflows.readthedocs.io/)
- [Examples](https://github.com/argoproj/argo-workflows/tree/main/examples)
- [Namespaced install](https://github.com/argoproj/argo-workflows/blob/main/docs/managed-namespace.md)
- [IDE yaml autocomplete for Workflows](https://argo-workflows.readthedocs.io/en/latest/ide-setup/)
- [Template Catalog: Free reusable templates for Argo Workflows](https://argoproj-labs.github.io/argo-workflows-catalog/)
