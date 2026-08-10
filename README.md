# The Platform Engineer's Handbook - Platform Gitops

This repository is the GitOps source of truth for all clusters managed by the platform team. Flux watches this repo and reconciles the declared state onto each cluster.

Each cluster entry in this repo does one thing: pull in tenants. Each tenant is an upstream application or service repo that manages its own Kubernetes resources. This repo only owns the wiring — it doesn't contain application manifests directly.


## Repository Structure

```
clusters/
├── platform-sandbox/          # Staging cluster
│   ├── kustomization.yaml     # Entry point — labels all resources env=platform-sandbox
│   └── tenants/
│       ├── kustomization.yaml # Lists active tenants
│       ├── platform-services/
│       │   ├── kustomization.yaml
│       │   └── platform-services.yaml   # GitRepository + Kustomization
│       └── demo-app/
│           ├── kustomization.yaml
│           └── demo-app.yaml            # GitRepository + Kustomization
└── app-dev/                   # Production cluster
    ├── kustomization.yaml
    └── tenants/
        ├── kustomization.yaml
        ├── platform-services/
        │   ├── kustomization.yaml
        │   └── platform-services.yaml
        └── demo-app/
            ├── kustomization.yaml
            └── demo-app.yaml
```

## Tenant Model

Each tenant consists of two Flux resources defined in `<tenant-name>.yaml`:

- **`GitRepository`** — points to the upstream repo and branch to watch
- **`Kustomization`** — points to a path within that repo containing the environment-specific manifests

The Kustomization `path` is environment-aware: the same upstream repo serves both clusters by having per-environment overlay directories (e.g. `./deploy/platform-sandbox` for staging, `./deploy/app-dev` for production).

The cluster-level `kustomization.yaml` adds an `env` label to every resource reconciled through it, which makes it easy to filter resources by cluster in tooling.

## Adding a New Tenant

1. **Create the tenant directory** under the target cluster:

   ```
   clusters/<cluster>/tenants/<tenant-name>/
   ```

2. **Create `<tenant-name>.yaml`** with a `GitRepository` and `Kustomization`:

   ```yaml
   ---
   apiVersion: source.toolkit.fluxcd.io/v1
   kind: GitRepository
   metadata:
     name: <tenant-name>
     namespace: flux-system
   spec:
     url: https://github.com/tpeh-demo-company/<repo>.git
     ref:
       branch: main
     interval: 1m
   ---
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: <tenant-name>
     namespace: flux-system
   spec:
     sourceRef:
       kind: GitRepository
       name: <tenant-name>
     path: ./deploy/<cluster>   # path inside the upstream repo
     interval: 1m
     timeout: 10m0s
     prune: true
     wait: true
   ```

3. **Create `kustomization.yaml`** in the tenant directory:

   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - <tenant-name>.yaml
   ```

4. **Register the tenant** by adding it to `clusters/<cluster>/tenants/kustomization.yaml`:

   ```yaml
   resources:
     - platform-services
     - <tenant-name>       # add this
   ```

Flux will pick up the change on its next reconciliation interval and begin syncing the upstream repo.

## Adding a New Cluster

1. Create `clusters/<cluster-name>/kustomization.yaml` following the same pattern as the existing clusters (set the `env` label to the cluster name).
2. Create `clusters/<cluster-name>/tenants/` and populate it following the tenant model above.
3. Bootstrap Flux on the new cluster pointing at this repo. ( Should be done via `platform-core`)

## Secrets (SOPS/age)

Tenants that manage secrets (currently `platform-services`) use SOPS with age for encryption. Flux decrypts them at reconciliation time using a key stored as a Kubernetes secret named `sops-age` in the `flux-system` namespace.

This secret must exist on the cluster before Flux can reconcile any tenant that declares `decryption.provider: sops`. If it's missing, the Kustomization will fail silently with a decryption error. ( Bootstrapped via `platform-core` also)
```