#!/usr/bin/env bash
# Recreate the whole environment from scratch.
# Usage: ./bootstrap.sh
set -euo pipefail

CLUSTER_NAME="demo-cluster"
REGION="us-east-1"
NODE_TYPE="t3.small"
NODES=2

echo "==> 1/5  Creating EKS cluster (15-20 min)..."
eksctl create cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --nodegroup-name workers \
  --node-type "$NODE_TYPE" \
  --nodes "$NODES" \
  --managed

echo "==> 2/5  Updating kubeconfig..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
kubectl get nodes

echo "==> 3/5  Installing ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/aws/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "==> 4/5  Installing Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --namespace argocd \
  --for=condition=available deployment/argocd-server \
  --timeout=300s

# Expose the Argo CD UI through a load balancer
kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"LoadBalancer"}}'

echo "==> 5/5  Registering the application with Argo CD..."
kubectl apply -f argocd-application.yaml

echo
echo "=============================================="
echo "Done. Argo CD will now sync the app from git."
echo
echo "Argo CD username: admin"
echo -n "Argo CD password: "
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo
echo
echo "Argo CD URL (may take 2-3 min for the ELB to come up):"
kubectl get svc argocd-server -n argocd \
  -o jsonpath='  https://{.status.loadBalancer.ingress[0].hostname}'
echo
echo
echo "App ingress endpoint:"
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='  {.status.loadBalancer.ingress[0].hostname}'
echo
echo "=============================================="
echo
echo "When you are finished, DELETE THE CLUSTER so it stops billing:"
echo "  eksctl delete cluster --name $CLUSTER_NAME --region $REGION"
