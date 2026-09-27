# The Platform Engineer's Handbook - Platform Gitops

This repository is the GitOps source of truth for all clusters managed by the platform team. Flux watches this repo and reconciles the declared state onto each cluster. It follows the [ControlPlane D1 reference architecture](https://github.com/controlplaneio-fluxcd/d1-fleet): the fleet only owns the wiring, and the manifests live in the tenant repos.

## Repository Structure

```
clusters/
├── platform-sandbox/          # Staging cluster (tracks `main`)
│   ├── runtime-info.yaml      # flux-runtime-info ConfigMap
│   └── infra-tenant.yaml      # Kustomization over ./tenants/infra/components
└── app-dev/                   # Production cluster (tracks `production`)
    ├── runtime-info.yaml
    └── infra-tenant.yaml
tenants/
└── infra/                     # Shared by every cluster
    └── components/
        ├── kustomization.yaml
        ├── rbac.yaml          # flux-infra ServiceAccount + cluster-admin binding
        ├── source.yaml        # GitRepository for platform-services
        ├── cert-manager.yaml  # Kustomization over ./environments/${ENVIRONMENT}/cert-manager
        ├── cloudflare.yaml    # ...one Kustomization per platform-services component
        ├── istio.yaml
        ├── kyverno.yaml
        ├── monitoring.yaml
        ├── opa.yaml
        └── reflector.yaml
```

The `FluxInstance` (created by `platform-core`) syncs `clusters/<cluster>`. The Flux Operator generates that path's `flux-system` manifests, so there is no `flux-system/` folder here.

## Runtime info

Each cluster has a `flux-runtime-info` ConfigMap (`clusters/<cluster>/runtime-info.yaml`):

| Key | staging (`platform-sandbox`) | production (`app-dev`) |
| --- | --- | --- |
| `ENVIRONMENT` | `staging` | `production` |
| `GIT_BRANCH` | `main` | `production` |
| `CLUSTER_NAME` | `platform-sandbox` | `app-dev` |
| `CLUSTER_DOMAIN` | `demo-company.site` | `demo-company.site` |

`infra-tenant.yaml` substitutes these into `tenants/infra/components` (`postBuild.substituteFrom`). Clusters therefore share the tenant manifests and differ only in runtime info. Escape any literal `${...}` in `tenants/` as `$${...}`.

Each `platform-services` component gets its own `Kustomization` in `tenants/infra`, matching the D1-fleet pattern of one `Kustomization` per component rather than one per tenant repo. `production` doesn't yet have `cloudflare/` or `kyverno/` under `environments/`, so those two `Kustomization`s fail to find their path on `app-dev` until that parity gap closes.

## Multitenancy

`platform-core` enables multitenancy on the Flux Operator and the `FluxInstance`. Cross-namespace references are refused, and any object without a `serviceAccountName` runs as the unprivileged `default` ServiceAccount. The infra tenant reconciles as `flux-infra` (cluster-admin); the sync `Kustomization` itself runs as `kustomize-controller`.

## Promotion

`main` is staging and `production` is production. Promote by merging `main` into `production` in the tenant repo (`platform-services`).

## Apps tenant

The `demo-app` tenant (`platform-demo-apps`) is on hold and returns as `tenants/apps/`.

## Adding a new cluster

1. Create `clusters/<cluster-name>/runtime-info.yaml` and `infra-tenant.yaml`, copying an existing cluster and changing the values (the `sourceRef` names the `GitRepository` the `FluxInstance` creates, which is the Pulumi stack name).
2. Bootstrap Flux through `platform-core` with a stack of the same name.

## Secrets (SOPS/age)

Each component `Kustomization` uses SOPS with age (`decryption.provider: sops`). Flux decrypts with the `sops-age` Secret in `flux-system`, created by `platform-core`. If it is missing, every component's Kustomization fails with a decryption error.
