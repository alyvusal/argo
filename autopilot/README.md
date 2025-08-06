# Autopilot

[back](../README.md)

ArgoCD must not be installed in advance, copilot will do this

- [Argo CD Autopilot](https://argocd-autopilot.readthedocs.io/en/stable/)

1. [Install](https://argocd-autopilot.readthedocs.io/en/stable/Installation-Guide)
2. [Do initial setup for copilot](https://argocd-autopilot.readthedocs.io/en/stable/Getting-Started/)
    - Create repo to store argocd copilot deployment files
    - `export GIT_REPO=https://github.com/alyvusal/sre.git/argocd/autopilot/deployments` (or with the flag: `--repo <url>`))
    - `export GIT_TOKEN=...`  (peronal token with repos access, or with the flag: `--git-token <token>`)
3. `argocd-autopilot repo bootstrap` - it will deploy argocd server, (use `--recover` to install argocd if repo already exists)

Testing

```bash
kubectl apply -f examples/AppProject.yaml
argocd-autopilot app create hello-world --app github.com/argoproj-labs/argocd-autopilot/examples/demo-app/ -p development --wait-timeout 2m
```

Uninstall ArgoCD and remove apps

```bash
# delete app
argocd-autopilot app delete hello-world -p testing

# delete all in repo including argocd itself
argocd-autopilot repo uninstall
```

## Recover

Recover ArgoCD cluster from [alyvusal/argocd-deployments](https://github.com/alyvusal/argocd-deployments)

```bash
argocd-autopilot repo bootstrap --recover
```
