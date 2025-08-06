# Image Updater

[back](../README.md)

- [Argo CD Image Updater](https://argocd-image-updater.readthedocs.io)

## [Installation](https://argocd-image-updater.readthedocs.io/en/stable/install/installation/)

```bash
kubectl apply -k k8s/kustomize
```

add following to `argocd-cm` ConfigMap

```yaml
data:
  # ...
  accounts.image-updater: apiKey
```

add following rbac rules to `argocd-rbac-cm` ConfigMap

```yaml
data:
  policy.default: role:readonly
  policy.csv: |
    p, role:image-updater, applications, get, */*, allow
    p, role:image-updater, applications, update, */*, allow
    g, image-updater, role:image-updater
```

Edit the `argocd-image-updater-config` ConfigMap and add the following keys

```yaml
data:
  applications_api: argocd
  # The address of Argo CD API endpoint - defaults to argocd-server.argocd
  argocd.server_addr: argocd-192.168.0.100.nip.io
  # Whether to use GRPC-web protocol instead of GRPC over HTTP/2
  argocd.grpc_web: "true"
  # Whether to ignore invalid TLS cert from Argo CD API endpoint
  argocd.insecure: "true"
  # Whether to use plain text connection (http) instead of TLS (https)
  argocd.plaintext: "false"
  # Log.level can be one of trace, debug, info, warn or error
  log.level: debug
```

After changing values in the ConfigMap, Argo CD Image Updater needs to be restarted for the changes to take effect

```bash
kubectl -n argocd rollout restart deployment argocd-image-updater
```

Configure API access token secret

```bash
TOKEN=$(argocd account generate-token --account image-updater --id image-updater --grpc-web)
kubectl create secret generic argocd-image-updater-secret \
  --from-literal argocd.token=$TOKEN --dry-run=client -o yaml |
  kubectl -n argocd apply -f -

kubectl -n argocd rollout restart deployment argocd-image-updater
```

## [Test](https://argocd-image-updater.readthedocs.io/en/stable/install/testing/)

[Install CLI](https://github.com/argoproj-labs/argocd-image-updater/)

```bash
argocd-image-updater test nginx

# helm for prod will udpate image automatic and write changes back to argocd manifest in k8s lcuster
kubectl apply -f examples/apps/Application.yaml
```

### [Argo Bundle](https://kubernetes-tutorial.schoolofdevops.com/argo_iamge_updater/)

```bash
kubectl -n argocd create secret generic git-creds \
  --from-literal=username=alyvusal \
  --from-literal=password=<GH TOKEN with write access to repository>

kubectl patch application --type=merge -n argocd demo-app-staging --patch-file image-updater/annotation_patch.yaml
```

## REFERENCE

- [Metrics](https://argocd-image-updater.readthedocs.io/en/stable/install/installation/#metrics)
- [Authentication](https://argocd-image-updater.readthedocs.io/en/stable/basics/authentication/#authentication-to-kubernetes)
