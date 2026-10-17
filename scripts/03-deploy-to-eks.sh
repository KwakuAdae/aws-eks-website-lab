#!/usr/bin/env bash
# Step 3: Deploy the website to EKS and print the load balancer URL.
set -euo pipefail
source "$(dirname "$0")/config.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo ">> Applying Kubernetes manifests (image: ${ECR_URI}:${IMAGE_TAG})..."
for f in "${ROOT}"/k8s/*.yaml; do
  envsubst '${ECR_URI} ${IMAGE_TAG}' < "$f"
  echo "---"
done | kubectl apply -f -

echo ">> Waiting for rollout..."
kubectl rollout status deployment/website -n website --timeout=180s
kubectl get pods -n website -o wide

echo ">> Waiting for the load balancer hostname (1-3 minutes)..."
for _ in $(seq 1 60); do
  LB=$(kubectl get svc website -n website -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  [[ -n "$LB" ]] && break
  sleep 5
done

echo ""
echo "✅ Website URL: http://${LB}"
echo "   (DNS can take another 1-2 minutes to resolve the first time.)"
