# HELIOS self-hosted runners (Actions Runner Controller)

Helm values for a [gha-runner-scale-set](https://github.com/actions/actions-runner-controller)
pool named **`helios-runners`**, registered against
`https://github.com/Yolkster64/helios-platform`, scaling **0 → 4** plain
(non-dind, non-kubernetes-mode) runner pods.

> **This is applied by you, to your cluster, with helm. Nothing in this
> repository's CI applies it.** Workflows only consume the pool via
> `runs-on: helios-runners`.

Chart version used throughout: **0.14.2** (the values schema in
`arc-values.yaml` mirrors `charts/gha-runner-scale-set/values.yaml` at that
tag). Prerequisites: a Kubernetes cluster, `kubectl`, and Helm ≥ 3.8 (OCI
registry support).

## 1. Install the controller (once per cluster)

```bash
helm install arc \
  --namespace arc-systems --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version 0.14.2
```

## 2. Create the auth secret (never committed, never inlined in values)

`arc-values.yaml` references a **pre-created** Kubernetes secret named
`helios-runners-github-secret`; the credential itself never appears in any
file in this repo. With a PAT held in an environment variable:

```bash
# PAT requirements for repo-level registration:
#   classic PAT  -> `repo` scope
#   fine-grained -> repository permission "Administration: Read and write"
export GH_RUNNER_PAT='<paste-your-PAT-here>'

kubectl create namespace arc-runners
kubectl create secret generic helios-runners-github-secret \
  --namespace arc-runners \
  --from-literal=github_token="${GH_RUNNER_PAT}"
unset GH_RUNNER_PAT
```

Preferred for anything shared (a PAT ties every runner to one human account):
a GitHub App secret instead —

```bash
kubectl create secret generic helios-runners-github-secret \
  --namespace arc-runners \
  --from-literal=github_app_id='<app-id>' \
  --from-literal=github_app_installation_id='<installation-id>' \
  --from-literal=github_app_private_key="$(cat helios-runners.private-key.pem)"
```

No change to `arc-values.yaml` is needed to switch — the secret name stays the same.

## 3. Install the runner scale set

From the repo root:

```bash
helm install helios-runners \
  --namespace arc-runners --create-namespace \
  --values infra/runners/arc-values.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.14.2
```

Verify:

```bash
helm list -n arc-runners
kubectl get pods -n arc-systems    # controller + a 'helios-runners-...-listener' pod
```

The pool then shows up under the repo's **Settings → Actions → Runners**
(after the first page load it may take a minute).

## 4. Use it from a workflow

```yaml
jobs:
  build:
    runs-on: helios-runners   # the scale-set name, singular
```

Scale sets do **not** match `[self-hosted, linux, x64]` label arrays — that is
the older RunnerDeployment model. With `minRunners: 0`, expect ~20–40 s of
queue time for the first job while a pod cold-starts; raise `minRunners` in
`arc-values.yaml` and `helm upgrade` if that latency matters.

## Uninstall

Order matters: remove scale sets before the controller.

```bash
helm uninstall helios-runners --namespace arc-runners
helm uninstall arc --namespace arc-systems
kubectl delete secret helios-runners-github-secret --namespace arc-runners
kubectl delete namespace arc-runners arc-systems   # optional, if nothing else lives there
```

If a scale set is deleted while jobs are running, in-flight jobs fail;
drain by letting the queue empty (or disable the workflows) first.
