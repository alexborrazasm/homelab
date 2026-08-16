#!/usr/bin/env bash
# Wrapper so k9s always points at kubernetes/kubeconfig - same pattern as
# kubectl.sh. k9s is a client, like kubectl - runs from your machine, not
# on any node.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

export KUBECONFIG="${PWD}/kubeconfig"

exec k9s "$@"
