# Secure Private AWS EKS Cluster with IAM Identity Center (SSO) & EKS Access Policies

Production-grade Terraform solution provisioning a **100% strictly private Amazon Elastic Kubernetes Service (EKS) cluster**, authenticated via **AWS IAM Identity Center (formerly AWS SSO)** and **EKS Access Entries**, and authorized via native **EKS Access Policies** across isolated namespaces (`dev`, `qa`, `production`).

---

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Security & Access Control Design (3 Groups)](#security--access-control-design-3-groups)
3. [Repository Structure](#repository-structure)
4. [Prerequisites](#prerequisites)
5. [AWS IAM Identity Center (SSO) Setup](#aws-iam-identity-center-sso-setup)
6. [Deployment Guide (Terraform)](#deployment-guide-terraform)
7. [Kubernetes Manifests Deployment](#kubernetes-manifests-deployment)
8. [Developer SSO Connectivity Workflow (`aws configure sso`)](#developer-sso-connectivity-workflow-aws-configure-sso)
9. [Comprehensive Verification Runbook](#comprehensive-verification-runbook)
10. [Teardown & Cleanup](#teardown--cleanup)
11. [Architecture Trade-Offs & Comparisons](#architecture-trade-offs--comparisons)

---

## Architecture Overview

```
                                      AWS Cloud (Region: ap-south-1)
 +----------------------------------------------------------------------------------------------------+
 |                                      VPC (10.0.0.0/16)                                             |
 |                                                                                                    |
 |  +-------------------------+      +--------------------------+     +----------------------------+  |
 |  | Public Subnet (Egress)  |      | Private Subnet A         |     | Private Subnet B           |  |
 |  |                         |      |                          |     |                            |  |
 |  |   [ NAT Gateway ]       |      |   [ EKS Cluster ENIs ]   |     |   [ Managed EKS Nodes ]    |  |
 |  |   [ Bastion Jumpbox ]   |      |   - 100% Private         |     |   - Node Group (t3.medium) |  |
 |  |   - SSH Gateway         |      |   - endpoint_private=true|     |   - Workloads (dev/qa/prod)|  |
 |  |   - Port-Forward Tunnel |      |   - endpoint_public=false|     |   - No Public IPs          |  |
 |  +----------|--------------+      +-------------|------------+     +--------------|-------------+  |
 |             |                                   |                                 |                |
 |             +-----------------------------------|---------------------------------+                |
 |                                                 v                                                  |
 |                                 +-------------------------------+                                  |
 |                                 |  Private EKS API Server (443) |                                  |
 |                                 +-------------------------------+                                  |
 +----------------------------------------------------------------------------------------------------+
                                                   ^
                                                   | Encrypted SSH Port Forward (6443 -> 443)
                                          +-----------------+
                                          | Bastion Jumpbox |
                                          +-----------------+
                                                   ^
                                                   | Temporary STS Credentials via SSO
                     +-----------------------------+-----------------------------+
                     |                                                           |
      +------------------------------+                           +-------------------------------+
      | AWS IAM Identity Center      |                           | Developer / Admin Workstation |
      | (SSO Login & Authentication) |                           | `aws configure sso`           |
      +--------------+---------------+                           | `aws sso login`               |
                     |                                           +---------------+---------------+
                     v                                                           |
          3 Permission Sets & Roles                                              |
  ───────────────────────────────────────                                        v
  1. EKS-Admin     ──▶ AmazonEKSClusterAdminPolicy (Cluster Scope)     ──▶ Full Cluster Admin
  2. EKS-ReadOnly  ──▶ AmazonEKSViewPolicy         (Cluster Scope)     ──▶ Read-Only (All Namespaces)
  3. EKS-Developer ──▶ AmazonEKSViewPolicy         (Namespace = 'dev') ──▶ Read-Only ('dev' ONLY)
```

---

## Security & Access Control Design (3 Groups)

The solution provides **3 clearly defined groups** with least-privilege boundary enforcement:

| Group Name | SSO Permission Set | EKS Access Policy | Policy Scope | Permissions & Restrictions |
|---|---|---|---|---|
| **Admin** | `EKS-Admin` | `AmazonEKSClusterAdminPolicy` | `cluster` | Full cluster-wide administration across all namespaces (`dev`, `qa`, `production`, `kube-system`). |
| **ReadOnly** | `EKS-ReadOnly` | `AmazonEKSViewPolicy` | `cluster` | Cluster-wide read-only view. Can inspect pods, services, and deployments in all namespaces; cannot create, edit, or delete any resource. |
| **Developer** | `EKS-Developer` | `AmazonEKSViewPolicy` | `namespace: dev` | **Read-Only access strictly to namespace `dev`**. Cannot create/modify in `dev`; access to `qa` or `production` returns `403 Forbidden`. |

### Zero Long-Lived Credentials
- No IAM access keys or secret keys are created or stored in Terraform state.
- Authentication relies on short-lived STS tokens generated dynamically via AWS IAM Identity Center (SSO).

---

## Repository Structure

```
INVI-GRID Project/
├── SETUP_GUIDE.md                   # Step-by-step SSO runbook with exact copy-paste commands
├── README.md                        # Master documentation, architecture guide & video screenplay
├── ARCHITECTURE_OPTIONS.md          # Architectural options & trade-off analysis (Pros & Cons)
├── bastion-key.pem                  # SSH private key for Bastion jumpbox
├── bastion-key.pub                  # SSH public key registered with AWS EC2
├── k8s/                             # Pure Kubernetes YAML Manifests
│   ├── 01-namespaces.yaml           # Isolated namespaces: dev, qa, production
│   ├── 02-rbac-developer.yaml       # Read-only Role & RoleBinding for 'dev-viewers' in 'dev'
│   ├── 04-rbac-viewer.yaml          # ClusterRoleBinding to 'view' ClusterRole for 'cluster-viewers'
│   ├── 05-rbac-admin.yaml           # ClusterRoleBinding to 'cluster-admin' for 'eks-admins'
│   ├── 06-sample-workloads.yaml     # Sample deployments in dev, qa, production
│   └── apply-all.sh                 # Unified script to apply all manifests
└── terraform/                       # Clean, Modular Infrastructure as Code
    ├── main.tf                      # Module orchestrator (vpc, vm, eks, iam)
    ├── variables.tf                 # Variables: region, cluster_name, SSO role ARNs
    ├── outputs.tf                   # Bastion IP, SSH command, user & SSO status outputs
    ├── versions.tf                  # AWS, TLS, and Local provider specifications
    ├── terraform.tfvars             # Environment variables
    ├── terraform.tfvars.example     # Template showing SSO Role ARN variables
    └── modules/
        ├── vpc/                     # Custom VPC, 2 public subnets, 2 private subnets, NAT Gateway
        ├── vm/                      # Bastion EC2 in public subnet with automated SSH key logic
        ├── eks/                     # 100% Private EKS 1.30 Cluster & Managed Node Group
        └── iam/                     # 3 Groups, EKS Access Entries & Policies, SSO Support
```

---

## Prerequisites

1. **AWS CLI v2**: [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
2. **Terraform (>= 1.5.0)**: [Install Terraform](https://developer.hashicorp.com/terraform/install)
3. **kubectl (>= 1.29)**: [Install kubectl](https://kubernetes.io/docs/tasks/tools/)
4. **OpenSSH Client**: Included natively in Windows 10/11 PowerShell and Linux/macOS.

---

## AWS IAM Identity Center (SSO) Setup

1. Open **AWS IAM Identity Center** in the AWS Console.
2. Under **Groups**, create 3 groups: `EKS-Admins`, `EKS-ReadOnly`, `EKS-Developers`.
3. Under **Permission sets**, create 3 permission sets:
   - `EKS-Admin` (attach inline policy with `eks:DescribeCluster` and `eks:ListClusters`)
   - `EKS-ReadOnly` (attach inline policy with `eks:DescribeCluster` and `eks:ListClusters`)
   - `EKS-Developer` (attach inline policy with `eks:DescribeCluster` and `eks:ListClusters`)
4. Under **AWS accounts**, assign the permission sets to the respective groups in your AWS account.
5. Retrieve the generated IAM SSO Role ARNs:
   ```bash
   aws iam list-roles \
     --query "Roles[?starts_with(RoleName, 'AWSReservedSSO_')].[RoleName,Arn]" \
     --output table
   ```

---

## Deployment Guide (Terraform)

### Step 1: Set SSO Role ARNs (Optional)
In `terraform/terraform.tfvars`:
```hcl
aws_region   = "ap-south-1"
cluster_name = "invigrid-eks"

sso_admin_role_arn     = "<SSO_ADMIN_ROLE_ARN>"
sso_readonly_role_arn  = "<SSO_READONLY_ROLE_ARN>"
sso_developer_role_arn = "<SSO_DEVELOPER_ROLE_ARN>"
```

### Step 2: Initialize and Deploy
```powershell
cd "e:\INVI-GRID Project\terraform"
terraform init
terraform apply -auto-approve
```

---

## Kubernetes Manifests Deployment

Because the cluster has `endpoint_public_access = false`, apply initial workloads via Bastion:

```powershell
$BASTION_IP = (terraform output -raw bastion_public_ip)
ssh -i "bastion-key.pem" ec2-user@$BASTION_IP
```

Inside Bastion:
```bash
aws eks update-kubeconfig --region ap-south-1 --name invigrid-eks
cd /home/ec2-user/k8s
./apply-all.sh
```

---

## Developer SSO Connectivity Workflow (`aws configure sso`)

On the developer workstation:

### 1. Configure SSO Session
```bash
aws configure sso
```
Provide the prompt details:
- **SSO start URL**: `https://my-sso-portal.awsapps.com/start`
- **SSO region**: `ap-south-1`
- Select permission set: `EKS-Developer`
- Profile name: `eks-developer`

### 2. Login via Browser
```bash
aws sso login --profile eks-developer
```

### 3. Update Kubeconfig
```bash
aws eks update-kubeconfig --name invigrid-eks --region ap-south-1 --profile eks-developer
```

### 4. Establish Encrypted SSH Tunnel
```powershell
$BASTION_IP = (terraform output -raw bastion_public_ip)
$EKS_ENDPOINT = (terraform output -raw eks_cluster_endpoint).Replace("https://", "")

ssh -i "bastion-key.pem" -N -L 6443:${EKS_ENDPOINT}:443 ec2-user@${BASTION_IP}
```

Point kubectl to localhost tunnel:
```powershell
kubectl config set-cluster (kubectl config view -o jsonpath='{.clusters[0].name}') `
  --server=https://localhost:6443 `
  --insecure-skip-tls-verify=true
```

---

## Comprehensive Verification Runbook

### Persona 1: Developer (`EKS-Developer`)
```bash
# 1. ALLOWED: View pods in 'dev' namespace
kubectl get pods -n dev
# -> SUCCESS

# 2. DENIED: Create workload in 'dev' (Read-Only restriction)
kubectl create deployment test-app --image=nginx -n dev
# -> Forbidden: User cannot create resource "deployments" in namespace "dev"

# 3. DENIED: Access unauthorized namespace 'qa'
kubectl get pods -n qa
# -> Forbidden: User cannot list resource "pods" in namespace "qa"

# 4. DENIED: Access production namespace
kubectl get pods -n production
# -> Forbidden: User cannot list resource "pods" in namespace "production"
```

### Persona 2: ReadOnly (`EKS-ReadOnly`)
```bash
# 1. ALLOWED: View pods in all namespaces
kubectl get pods -n dev
kubectl get pods -n qa
kubectl get pods -n production
# -> SUCCESS

# 2. DENIED: Create or modify workloads anywhere
kubectl create deployment test-app --image=nginx -n dev
# -> Forbidden
```

### Persona 3: Admin (`EKS-Admin`)
```bash
# 1. ALLOWED: Cluster-wide inspection
kubectl get pods -A
kubectl get nodes
# -> SUCCESS

# 2. ALLOWED: Workload creation in any namespace
kubectl create deployment admin-test --image=nginx -n production
kubectl delete deployment admin-test -n production
# -> SUCCESS
```

---

## Teardown & Cleanup

```powershell
cd "e:\INVI-GRID Project\terraform"
terraform destroy -auto-approve
```

---

## Architecture Trade-Offs & Comparisons

See [ARCHITECTURE_OPTIONS.md](file:///e:/INVI-GRID%20Project/ARCHITECTURE_OPTIONS.md) for full trade-off analysis comparing AWS SSO + EKS Access Policies vs IAM Users and External OIDC.
