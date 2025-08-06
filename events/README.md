# Argo Events

[back](../README.md)

- Event Source: Monitors source for event (ex: GitHub change events, [poller like app](./examples/argo-bundle-test/poller-cronjob.yaml)) needed to trigger Event source)
- Event Bus: Send info to Sensor to create action on Argo Workflow
- Sensor: Which activates on updated to event source and triggers the workflow

```bash
# install all-in-one
kubectl apply -k k8s/kustomize
```

## Usage

## EventBus

Create EventBus

```bash
# Create a service account with RBAC settings to allow the sensor to trigger workflows, and allow workflows to function.
#   sensor rbac
kubectl -n argo-events apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/rbac/sensor-rbac.yaml
#   workflow rbac
kubectl -n argo-events apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/rbac/workflow-rbac.yaml
# Deploy the eventbus
kubectl -n argo-events apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml
```

### Github

- [Set Github credentials](../README.md#Github)
- [Set Dockerhub credentials](../README.md#dockerhub)

#### Setup Components to Trigger CI Pipeline

```bash
# Create an Argo Events EventSource and Sensor to handle the events sent by your polling job.
kubectl apply -f examples/argo-bundle-lab/webook-eventsource.yaml
# create sensor
kubectl apply -f examples/argo-bundle-lab/polling-sensor.yaml

# create workflow template
kubectl apply -f ../workflows/examples/WorkflowTemplate/argo-bundle-lab/demo-app-template.yaml

# validate
kubectl get workflowtemplate -A  # or
argo template list -A

```

#### Deploy GitHub Poller

After setting up the event flow, you also need to set up something which will trigger the event source on changes to GitHub.

You could do this in two ways

- Using Webhooks : You could expose the event source service to outside and let GitHub trigger a webhook whenever there is a push event. This is useful if your event source can be publically available (GitHub can connect to it).
- In-cluster Polling : You could alternately set up in cluster system to periodically poll GitHub for changes, and trigger the event source. This is useful when you can not expose event source service pubically, and are running your cluster in a private network.

```bash
# create poller job
kubectl apply -f examples/argo-bundle-lab/poller-cronjob.yaml
```

### Minio

```bash
# We want Argo Events to trigger a workflow when a file is added to minio. In order to achieve this,
# we will add a minio eventsource which will listen for minio events.
# https://argoproj.github.io/argo-events/eventsources/setup/minio/
kubectl apply -n argo-events -f minio-secret.yaml
# We can see that it is set to observe the minio bucket called argoproj.
# If we create a file, or delete a file in this bucket, we will trigger an event
kubectl apply -n argo-events -f minio-eventsource.yaml

# We need to install a Sensor that is called by the EventSource.
# The Sensor is responsible for triggering the creation of a workflow when an event is received
kubectl apply -n argo-events -f minio-sensor.yaml

# Resolve RBAC issues and re-trigger
# Kubernetes RBAC is a deep subject. Further reading can be found in the Kubernetes Documentation.

# Our sensor is running using the default Service Account in the argo-events namespace. This service account does not have permission to create workflows in the argo namespace. We therefore need to give it permission to do so.

# You may choose to create a completely new Service Account for this purpose. For brevity, we will just grant the default Service Account permission to create workflows. We do this using a ClusterRole, and a ClusterRoleBinding to bind the role to the Serviceaccount.
kubectl apply -n argo-events -f sa.yaml
```

Now we can attempt to re-trigger our workflow. We can do this by deleting the file we uploaded to minio. This will trigger a delete event, which will trigger our workflow.

In case you need to, port-forward the minio UI. Then log in and delete a file from the argoproj bucket.

## REFERENCE

- [killercoda](https://killercoda.com/argoproj/course/argo-workflows/argo-events)
