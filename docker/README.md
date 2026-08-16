# docker/ cheat sheet

Management host is `panel` (`192.168.9.10`, LAN - not DMZ, since it holds
cluster-wide control/observability, not a public-facing service): Komodo
now, a Headscale exit node and Grafana planned later.

Docker itself and the Komodo stack (Mongo + Core + Periphery) are
installed by Ansible - see `ansible/roles/docker`, `ansible/roles/komodo`,
`ansible/playbooks/docker.yml`. This directory is where the actual
**application** stacks live, as plain `docker-compose.yml` files Komodo
watches in git - the docker equivalent of `kubernetes/apps/` in the old
setup, minus the extra layers.

## Bootstrap (one time, per management host)

```bash
cd ansible
uv run ansible-playbook playbooks/docker.yml --check --diff
uv run ansible-playbook playbooks/docker.yml
```

This installs Docker and brings up Komodo at `http://<host-ip>:9120`
(`admin` / the password in `ansible/roles/komodo/files/.env`, gitignored -
generate a fresh `.env` from `.env.example` with `openssl rand -hex N`
before the first run on a new host).

## Adding a service

Unlike the old ArgoCD setup, Komodo's git sync is configured **in its
own UI**, not by adding a file here and hoping something notices:

1. Add `docker/stacks/<name>/compose.yaml` to this repo, commit, push.
2. In Komodo: **Stacks -> Create Stack**, point it at this repo +
   `docker/stacks/<name>/compose.yaml`.
3. Turn on **Poll for Updates** (or configure the GitHub webhook for
   instant sync instead of polling) - from then on, a push to `main`
   redeploys the stack automatically, same spirit as the old
   `kubectl apply` -> `git push` workflow.

Secrets: same rule as ever - never in the compose file or git. Put them
in that stack's own `.env` on the host (Komodo can manage per-stack
environment variables directly in its UI without them touching the repo
at all).

## Adding another Docker host later

Komodo Core is meant to manage multiple servers - **don't** repeat the
full `komodo` role on a second host. Instead:

1. Run the `docker` role there (Docker + the netfilter module fix).
2. Install just the Periphery agent, pointed at this Core - either the
   [standalone systemd install](https://komo.do/docs/setup/connect-servers),
   or a minimal periphery-only compose service. Worth its own Ansible role
   (`komodo_agent` or similar) once there's a second host to justify it -
   no reason to build it speculatively now.
