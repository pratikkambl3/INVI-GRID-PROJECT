#!/bin/bash
set -ex

# Log all output to /var/log/user-data.log and console
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=========================================================="
echo " Starting Bastion Jumpbox Provisioning                    "
echo "=========================================================="

# 1. Update and install basic tools
dnf update -y
dnf install -y git jq tmux tar gzip

# 2. Install kubectl 1.30
echo ">> Installing kubectl 1.30..."
curl -LO "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/kubectl

# 3. Install Helm 3
echo ">> Installing Helm 3..."
curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 /tmp/get_helm.sh
/tmp/get_helm.sh
rm -f /tmp/get_helm.sh

# Verify installations
/usr/local/bin/kubectl version --client --output=yaml || true
/usr/local/bin/helm version || true

# 4. Create Kubernetes workspace directory
mkdir -p /home/ec2-user/k8s

# --- 01-namespaces.yaml ---
cat << 'K8S_EOF' > /home/ec2-user/k8s/01-namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
  labels:
    environment: development
---
apiVersion: v1
kind: Namespace
metadata:
  name: qa
  labels:
    environment: quality-assurance
---
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    environment: production
K8S_EOF

# --- 02-rbac-developer.yaml ---
cat << 'K8S_EOF' > /home/ec2-user/k8s/02-rbac-developer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: dev-read-only-role
  namespace: dev
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-read-only-binding
  namespace: dev
subjects:
  - kind: Group
    name: dev-viewers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: dev-read-only-role
  apiGroup: rbac.authorization.k8s.io
K8S_EOF

# --- 04-rbac-viewer.yaml ---
cat << 'K8S_EOF' > /home/ec2-user/k8s/04-rbac-viewer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-readonly-binding
subjects:
  - kind: Group
    name: cluster-viewers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
K8S_EOF

# --- 05-rbac-admin.yaml ---
cat << 'K8S_EOF' > /home/ec2-user/k8s/05-rbac-admin.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: eks-admin-binding
subjects:
  - kind: Group
    name: eks-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
K8S_EOF

# --- 06-sample-workloads.yaml ---
cat << 'K8S_EOF' > /home/ec2-user/k8s/06-sample-workloads.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dev-sample-app
  namespace: dev
  labels:
    app: dev-sample-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: dev-sample-app
  template:
    metadata:
      labels:
        app: dev-sample-app
    spec:
      containers:
        - name: nginx
          image: public.ecr.aws/nginx/nginx:alpine
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qa-test-app
  namespace: qa
  labels:
    app: qa-test-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: qa-test-app
  template:
    metadata:
      labels:
        app: qa-test-app
    spec:
      containers:
        - name: nginx
          image: public.ecr.aws/nginx/nginx:alpine
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-secure-app
  namespace: production
  labels:
    app: prod-secure-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: prod-secure-app
  template:
    metadata:
      labels:
        app: prod-secure-app
    spec:
      containers:
        - name: nginx
          image: public.ecr.aws/nginx/nginx:alpine
K8S_EOF

# --- apply-all.sh ---
cat << 'SCRIPT_EOF' > /home/ec2-user/k8s/apply-all.sh
#!/bin/bash
set -e
echo "=========================================================="
echo " Applying EKS Namespaces, RBAC, and Sample Workloads      "
echo "=========================================================="
kubectl apply -f /home/ec2-user/k8s/01-namespaces.yaml
kubectl apply -f /home/ec2-user/k8s/02-rbac-developer.yaml
kubectl apply -f /home/ec2-user/k8s/04-rbac-viewer.yaml
kubectl apply -f /home/ec2-user/k8s/05-rbac-admin.yaml
kubectl apply -f /home/ec2-user/k8s/06-sample-workloads.yaml
echo ""
echo ">> All Kubernetes resources applied successfully!"
SCRIPT_EOF
chmod +x /home/ec2-user/k8s/apply-all.sh

# --- setup-kubeconfig.sh ---
cat << 'SCRIPT_EOF' > /home/ec2-user/setup-kubeconfig.sh
#!/bin/bash
aws eks update-kubeconfig --region ${aws_region} --name ${cluster_name}
echo "Kubeconfig configured for ${cluster_name}!"
SCRIPT_EOF
chmod +x /home/ec2-user/setup-kubeconfig.sh

# --- test-rbac.sh ---
cat << 'SCRIPT_EOF' > /home/ec2-user/test-rbac.sh
#!/bin/bash
echo "=========================================================="
echo "   EKS IAM Authentication & Kubernetes RBAC Verification  "
echo "=========================================================="
echo "Current caller identity:"
aws sts get-caller-identity
echo ""
echo "Testing access with current credentials:"
echo ">> 1. 'dev' namespace pods:"
kubectl get pods -n dev || echo ">> Failed in dev"
echo ">> 2. 'qa' namespace pods:"
kubectl get pods -n qa || echo ">> Failed in qa"
echo ">> 3. 'production' namespace pods:"
kubectl get pods -n production || echo ">> Failed in production"
SCRIPT_EOF
chmod +x /home/ec2-user/test-rbac.sh

# Fix ownership
chown -R ec2-user:ec2-user /home/ec2-user/k8s /home/ec2-user/*.sh

echo "=========================================================="
echo " Bastion Jumpbox Provisioning Complete!                   "
echo "=========================================================="

