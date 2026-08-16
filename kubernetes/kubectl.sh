#!/usr/bin/env bash
# Wrapper so kubectl always points at kubernetes/kubeconfig without needing
# a manual `export KUBECONFIG` - same pattern as terraform/tofu.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

export KUBECONFIG="${PWD}/kubeconfig"

exec kubectl "$@"
