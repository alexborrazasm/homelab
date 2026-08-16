#!/usr/bin/env bash
# Copies k3s's own kubeconfig off k3s-server and patches the server URL
# (k3s.yaml hardcodes 127.0.0.1, correct only when run on the node itself)
# so kubectl can be run from this machine instead of over SSH.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

set -a
source .env
set +a

ssh "alex@${K3S_SERVER_IP}" sudo cat /etc/rancher/k3s/k3s.yaml \
  | sed "s/127.0.0.1/${K3S_SERVER_IP}/" \
  > kubeconfig
chmod 600 kubeconfig

echo "Wrote kubernetes/kubeconfig - use ./kubectl.sh instead of kubectl from now on"
