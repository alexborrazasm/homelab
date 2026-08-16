#!/usr/bin/env bash
# Applies secrets that live in .env (gitignored) to the cluster - kept out
# of the plain YAML manifests so no token ever gets written to a file that
# could be committed by accident. Idempotent (dry-run|apply), safe to
# re-run any time .env changes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

set -a
source .env
set +a

./kubectl.sh create namespace cert-manager \
  --dry-run=client -o yaml | ./kubectl.sh apply -f -

./kubectl.sh create secret generic cloudflare-api-token-secret \
  --namespace cert-manager \
  --from-literal=api-token="${CLOUDFLARE_API_TOKEN}" \
  --dry-run=client -o yaml | ./kubectl.sh apply -f -
