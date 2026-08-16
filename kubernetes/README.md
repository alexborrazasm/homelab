# kubernetes/ cheat sheet

GitOps via ArgoCD, "app of apps" pattern. Two things are ever applied by
hand: ArgoCD itself, and `argocd/root.yaml` (the one Application that
watches `apps/` and takes over from there). Everything else - cert-manager,
the `ClusterIssuer`s - is a file under `apps/` or a directory it points
at: edit, commit, **push to `main`** (ArgoCD pulls from the GitHub
remote, not your working tree - a change only takes effect once pushed),
and ArgoCD syncs it within ~3 min on its own (or click Sync in the UI for
immediately).

## Prerequisites

`kubectl` on your machine (not on any node - see Access below):

```bash
sudo dnf install kubectl
```

If it's not in the repos yet, grab the upstream binary instead:

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

## Access

kubectl runs from your machine, not by SSHing into `k3s-server` - same
pattern as `terraform/tofu.sh` running against the Proxmox API remotely
instead of from `pve` itself. Use `./kubectl.sh` instead of a bare
`kubectl` - it points at `kubernetes/kubeconfig` for you, no manual
`export KUBECONFIG` needed.

```bash
cd kubernetes
cp .env.example .env    # fill in K3S_SERVER_IP (and CLOUDFLARE_API_TOKEN, needed further down)

./fetch-kubeconfig.sh        # scp's k3s.yaml off k3s-server, patches 127.0.0.1 -> its real IP
./kubectl.sh get nodes
```

Re-run `fetch-kubeconfig.sh` if the server is ever rebuilt - the
token/CA embedded in the kubeconfig are generated fresh on first k3s
install (`ansible/roles/k3s`), so a rebuilt server invalidates the copy
you have.

## ArgoCD (bootstrap - one time)

```bash
./kubectl.sh create namespace argocd
./kubectl.sh apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.1/manifests/install.yaml
./kubectl.sh -n argocd rollout status deploy/argocd-server

./kubectl.sh apply -f argocd/root.yaml
```

`--server-side --force-conflicts`, not plain `apply` - the
`applicationsets.argoproj.io` CRD in this manifest is big enough that a
regular client-side apply fails with `metadata.annotations: Too long: may
not be more than 262144 bytes` (kubectl stores the whole previous config
in an annotation to diff against, and that CRD's schema alone blows past
the 256KiB annotation limit). Server-side apply tracks ownership via
`managedFields` instead, so it doesn't hit this. `--force-conflicts` is
needed if you already ran a plain `apply` once and it partially
succeeded, since those resources are now owned by a different field
manager.

That last command is the last time you `apply` anything for `cert-manager`
or the `ClusterIssuer`s by hand - see `apps/cert-manager.yaml` and
`apps/cluster-issuers.yaml`; once they're committed and pushed to `main`,
`root.yaml` picks them up and syncs both automatically.

Reach the UI (optional - everything above works without it):

```bash
./kubectl.sh -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
./kubectl.sh -n argocd port-forward svc/argocd-server 8080:443   # https://localhost:8080, user "admin"
```

## cert-manager + Cloudflare DNS-01 (wildcard certs)

GitOps-managed (see above) - `apps/cert-manager.yaml` installs the chart,
`apps/cluster-issuers.yaml` points at `cert-manager/` in this repo for
the two `ClusterIssuer`s. The one thing that's still manual, on purpose -
secrets never live in git:

```bash
./apply-secrets.sh      # creates cloudflare-api-token-secret in the cert-manager namespace
```

Use `letsencrypt-cloudflare-staging` on a `Certificate`/Ingress while
testing, `letsencrypt-cloudflare` only once that issues cleanly - see the
rate-limit comment in `cert-manager/cluster-issuer-staging.yaml`.
