# docker/

Service deployment - Docker + Komodo.

## Layout

`panel` runs the Komodo stack (Core + Mongo + Periphery). Other hosts
(`frontend`, `iot`, ...) run just a Periphery agent, managed by `panel`'s
Komodo. Both installed by Ansible - see `ansible/roles/docker`,
`ansible/roles/komodo`, `ansible/roles/komodo_agent`,
`ansible/playbooks/docker.yml`.

Everything lives under `/srv/docker`, owned by a dedicated `docker`
user/group (fixed UID:GID `900:900` on every host - reached via
`sudo su docker`, no direct login). Data directories are bind mounts next
to each `compose.yaml`, not named Docker volumes, for easy NFS migration
later.

Application stacks live in `docker/stacks/<name>/compose.yaml`.

## Bootstrap (one time, per management host)

```bash
cd ansible
uv run ansible-playbook playbooks/docker.yml --check --diff
uv run ansible-playbook playbooks/docker.yml
```

Brings up Komodo at `http://<host-ip>:9120` (`admin` / the password in
`ansible/roles/komodo/files/.env`, gitignored - generate one from
`.env.example` before the first run).

## Adding a service

Komodo's git sync is configured in its own UI, not auto-discovered:

1. Add `docker/stacks/<name>/compose.yaml`, commit, push.
2. In Komodo: **Stacks -> Create Stack**, point it at this repo + path.
3. Enable **Poll for Updates** (or a webhook) - pushes redeploy it from then on.

Secrets go in that stack's own `.env` on the host via Komodo's UI, never
in the compose file or git.

## Adding another Docker host

Put the new VM in the `docker` + `komodo_agent` `ansible_groups` (see
`terraform/locals.tf`) instead of repeating the full `komodo` role -
`komodo_agent` installs just Periphery, trusting Core's key automatically
via Ansible facts (no key ever committed to git).

One manual step in Komodo's UI once Periphery is up: paste its public key
(`sudo cat /srv/docker/komodo-agent/data/keys/periphery.pub`) into the
Server resource. Leave "Address" blank and don't open any inbound port -
Periphery only ever dials out to Core.
