#!/usr/bin/env bash
# End-to-end: AKS Automatic cluster + Actions Runner Controller + one runner scale set.
# Usage: source env.sh && ./run.sh [cluster|arc|runners|test|cleanup]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${GITHUB_TOKEN:?export GITHUB_TOKEN (PAT with repo scope, or use a GitHub App)}"
: "${GITHUB_CONFIG_URL:?source env.sh first}"

cluster() {
  az group create --name "$RG" --location "$LOCATION" -o none
  az aks create --resource-group "$RG" --name "$CLUSTER" --location "$LOCATION" \
    --sku automatic --no-ssh-key -o none
  AKS_ID=$(az aks show -g "$RG" -n "$CLUSTER" --query id -o tsv)
  ME=$(az ad signed-in-user show --query id -o tsv)
  az role assignment create --assignee "$ME" \
    --role "Azure Kubernetes Service RBAC Cluster Admin" --scope "$AKS_ID" -o none
  az aks get-credentials -g "$RG" -n "$CLUSTER" --format exec --overwrite-existing
  kubectl get nodes
}

arc() {
  helm upgrade --install arc \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
    --namespace "$ARC_SYSTEMS_NAMESPACE" --create-namespace --wait --timeout 10m \
    -f "$HERE/arc-controller-values.yaml"
  kubectl -n "$ARC_SYSTEMS_NAMESPACE" get pods
}

runners() {
  kubectl create namespace "$ARC_RUNNERS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  printf '%s' "$GITHUB_TOKEN" | kubectl create secret generic github-pat \
    --namespace "$ARC_RUNNERS_NAMESPACE" --from-file=github_token=/dev/stdin \
    --dry-run=client -o yaml | kubectl apply -f -
  envsubst '${GITHUB_CONFIG_URL}' < "$HERE/arc-runner-set-values.yaml" \
    | helm upgrade --install "$RUNNER_SET_NAME" \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
        --namespace "$ARC_RUNNERS_NAMESPACE" --create-namespace --wait --timeout 10m -f -
  kubectl -n "$ARC_SYSTEMS_NAMESPACE" get pods
  kubectl -n "$ARC_RUNNERS_NAMESPACE" get autoscalingrunnersets
}

test() {
  gh workflow run arc-automatic-validation.yml --repo "$GITHUB_OWNER/$GITHUB_REPO" --ref "$GITHUB_BRANCH"
  echo "watch pods:  kubectl -n $ARC_RUNNERS_NAMESPACE get pods -w"
  echo "watch nodes: kubectl get nodes -w"
  echo "watch run:   gh run watch --repo $GITHUB_OWNER/$GITHUB_REPO"
}

cleanup() {
  helm uninstall "$RUNNER_SET_NAME" -n "$ARC_RUNNERS_NAMESPACE" || true
  helm uninstall arc -n "$ARC_SYSTEMS_NAMESPACE" || true
  kubectl delete namespace "$ARC_RUNNERS_NAMESPACE" "$ARC_SYSTEMS_NAMESPACE" --ignore-not-found
  az group delete --name "$RG" --yes --no-wait
}

case "${1:-all}" in
  cluster|arc|runners|test|cleanup) "$1" ;;
  all) cluster; arc; runners; test ;;
  *) echo "usage: $0 [cluster|arc|runners|test|cleanup]"; exit 1 ;;
esac
