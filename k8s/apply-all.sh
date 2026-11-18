#!/bin/bash
set -e

echo "=========================================================="
echo " Applying EKS Namespaces, RBAC, and Sample Workloads"
echo "=========================================================="

echo ">> 1. Creating Namespaces (dev, qa, production)..."
kubectl apply -f 01-namespaces.yaml

echo ">> 2. Applying Developer RBAC (Read-Only in 'dev')..."
kubectl apply -f 02-rbac-developer.yaml

echo ">> 3. Applying Cluster-Wide ReadOnly RBAC (View ClusterRole for 'cluster-viewers')..."
kubectl apply -f 04-rbac-viewer.yaml

echo ">> 4. Applying Cluster Admin RBAC (ClusterRoleBinding for 'eks-admins')..."
kubectl apply -f 05-rbac-admin.yaml

echo ">> 5. Deploying Sample Workloads across namespaces..."
kubectl apply -f 06-sample-workloads.yaml

echo ""
echo "=========================================================="
echo " Deployment Summary"
echo "=========================================================="
kubectl get namespaces
echo ""
echo "Deployments in 'dev':"
kubectl get deployments -n dev
echo ""
echo "Deployments in 'qa':"
kubectl get deployments -n qa
echo ""
echo "Deployments in 'production':"
kubectl get deployments -n production
echo ""
echo ">> All Kubernetes resources applied successfully!"
