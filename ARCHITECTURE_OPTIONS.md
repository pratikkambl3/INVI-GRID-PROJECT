# Architectural Design & Options Analysis

**Project**: Private Amazon EKS Cluster with IAM Authentication & Kubernetes Native RBAC  
**Scope**: Architectural Trade-Off Analysis, Authentication Modes, Connectivity Models, Pros & Cons  

---

## 1. Executive Summary

This document evaluates the architectural design decisions and trade-offs for deploying a **strictly private Amazon Elastic Kubernetes Service (EKS) cluster** with multi-user isolation across isolated namespaces (`dev`, `qa`, `production`).

In enterprise and compliance-focused environments, exposing Kubernetes API endpoints to the public internet presents significant risks:
- Distributed denial-of-service (DDoS) against API servers
- Vulnerability to zero-day API server exploits
- Exposure of control plane attack surfaces

By enforcing `endpoint_public_access = false` and `endpoint_private_access = true`, the cluster API server is reachable solely from within private VPC subnets. This document evaluates the trade-offs across three architectural pillars:
1. **Cluster Authentication & Authorization Models**
2. **Private Cluster Connectivity & Developer Workflow**
3. **Namespace Multi-Tenancy & RBAC Enforcement**

---

## 2. Pillar 1: Cluster Authentication & Authorization Models

```
                      Authentication & Authorization Architectures

  [ ARCHITECTURE 1 (Dual-Supported) ]        [ ARCHITECTURE 2 (Supported) ]        [ ARCHITECTURE 3 ]
  IAM Users + EKS Access Entries             AWS SSO + EKS Access Policies         External OIDC (Keycloak/Dex)
  
  AWS IAM User (IAM Credentials)             IAM Identity Center (SSO)             Third-party IdP / OIDC
                 │                                        │                                       │
                 ▼                                        ▼                                       ▼
  aws_eks_access_entry                       aws_eks_access_entry                  OIDC Token to API Server
  (AmazonEKS Policies / Groups)              (AmazonEKS Policies / Groups)                        │
                 │                                        │                                       ▼
                 ▼                                        ▼                                K8s RBAC Roles
  Native Kubernetes RBAC                     AWS EKS Policy Engine                 (Cluster & Namespaces)
  (Roles & RoleBindings)                     (ClusterAdmin, ViewPolicy)
```

### Comprehensive Comparison Matrix

| Criteria | Architecture 1: IAM Users + K8s RBAC | Architecture 2: AWS SSO + EKS Access Policies (Supported) | Architecture 3: External OIDC (Keycloak / Dex) | Architecture 4: Legacy `aws-auth` ConfigMap |
|---|---|---|---|---|
| **Authentication Source** | AWS IAM Users | AWS IAM Identity Center (SAML / Org) | OIDC Identity Provider (Keycloak, Okta) | AWS IAM Users / Roles |
| **Authorization Plane** | **Pure Kubernetes API** (`Role`, `RoleBinding`) | **AWS EKS Control Plane** (Access Policies) | Kubernetes API (`Role`, `RoleBinding`) | Kubernetes API (`Role`, `RoleBinding`) |
| **AWS Infrastructure Overhead** | Minimal (Zero extra services) | High (Requires AWS Organizations, SSO Directory) | High (Requires running IdP servers/DB) | Low (Single ConfigMap) |
| **Namespace Granularity** | **Unlimited fine-grained RBAC** (sub-resources, verbs, CRDs) | Coarse (AmazonEKSEditPolicy, AmazonEKSViewPolicy) | Unlimited fine-grained RBAC | Unlimited fine-grained RBAC |
| **Secrets Protection** | **Explicitly configurable** (exclude `secrets` from Role) | Predefined (EditPolicy includes secrets) | Explicitly configurable | Explicitly configurable |
| **Setup Complexity** | **Low to Moderate** (Fully automated via Terraform) | High (Cross-account permission sets) | Very High (Self-hosted clusters/certs) | Low (Deprecated) |
| **AWS Deprecation Status** | Modern standard (`API_AND_CONFIG_MAP`) | Modern standard | Supported via EKS OIDC flag | **Deprecated** by AWS |

---

### Detailed Pros & Cons: Authentication Architectures

#### Architecture 1: AWS IAM Users + EKS Access Entries + Pure Kubernetes RBAC (Implemented)
* **How it works**:
  1. Each user is an IAM User (with credentials/keys managed securely on-demand rather than stored in Terraform state).
  2. The EKS cluster creates `aws_eks_access_entry` mapping the IAM User ARN to Kubernetes groups (`dev-developers`, `qa-developers`, `dev-viewers`, `eks-admins`).
  3. No AWS-managed access policies are attached.
  4. Native Kubernetes `Role` and `RoleBinding` manifests define exact permissions per namespace.
* **Pros**:
  - **Maximum Security & Least Privilege**: Can restrict individual Kubernetes API groups, resources, and verbs (e.g., allow `deployments`, but deny `secrets`). EKS-managed policies do not offer this granularity.
  - **Zero External Dependencies**: Does not require AWS Organizations, Identity Center, or external identity software.
  - **100% Infrastructure as Code**: The entire lifecycle is managed via Terraform and standard Kubernetes YAML.
  - **Portability**: Kubernetes RBAC manifests can be reused across any Kubernetes distribution (EKS, GKE, AKS, or on-premises).
* **Cons**:
  - Requires managing IAM user credentials out-of-band or via identity management.

---

#### Architecture 2: AWS IAM Identity Center (SSO) + EKS-Managed Access Policies
* **How it works**: Uses centralized SSO permission sets and AWS EKS Access Policies (`AmazonEKSEditPolicy`, `AmazonEKSViewPolicy`, `AmazonEKSClusterAdminPolicy`).
* **Pros**:
  - Centralized employee lifecycle management; short-lived STS tokens instead of static access keys.
  - Zero Kubernetes YAML manifests required for basic namespaces.
* **Cons**:
  - **Lack of granular control**: `AmazonEKSEditPolicy` grants broad permissions including read/write access to Kubernetes `Secrets`. Cannot restrict specific verbs or sub-resources.
  - **Requires AWS Organizations**: Cannot be deployed on standalone AWS root accounts without setting up an entire Organization structure.
  - High operational complexity and console dependency.

---

#### Architecture 3: External OIDC Provider (Keycloak / Dex)
* **How it works**: Deploying an open-source OIDC provider that issues signed JWT tokens mapped directly into Kubernetes API server OIDC flags.
* **Pros**:
  - Cloud-agnostic identity management.
  - No AWS IAM identities needed for developers.
* **Cons**:
  - Significant operational burden: requires deploying, scaling, backing up, and patching a high-availability database and auth server.
  - Unnecessary infrastructure overhead for small-to-medium teams.

---

#### Architecture 4: Legacy `aws-auth` ConfigMap
* **How it works**: Storing IAM ARN mappings inside the `aws-auth` ConfigMap in `kube-system`.
* **Pros**:
  - Backward compatible with older EKS clusters.
* **Cons**:
  - **Deprecated by AWS** in favor of Access Entries.
  - **Fragile YAML**: A single indentation error in `aws-auth` can corrupt cluster access and permanently lock out all administrators.
  - **Chicken-and-egg problem**: Terraform cannot easily apply `aws-auth` to a private cluster from an external workstation before networking is established.

---

## 3. Pillar 2: Private Cluster Connectivity & Management Plane

When `endpoint_public_access = false`, the Kubernetes API server network interface (ENI) listens strictly on private VPC IP addresses. External developers cannot reach `https://<cluster-hash>.yl4.<region>.eks.amazonaws.com` over the public internet.

Below are the primary connectivity options:

```
  +----------------------------------------------------------------------------------------------------+
  |                                      AWS VPC (10.0.0.0/16)                                         |
  |                                                                                                    |
  |  +-------------------------+      +--------------------------+     +----------------------------+  |
  |  | Public Subnet (Egress)  |      | Private Subnet A         |     | Private Subnet B           |  |
  |  |                         |      |                          |     |                            |  |
  |  |   [ NAT Gateway ]       |      |   [ EKS Cluster ENIs ]   |     |   [ Managed EKS Nodes ]    |  |
  |  |   [ Bastion Jumpbox ]   |      |   - endpoint_private=true|     |   - Node Group (t3.medium) |  |
  |  |   - SSH Gateway         |      |   - endpoint_public=false|     |   - Workloads (dev/qa/prod)|  |
  |  |   - Port-Forward Tunnel |      |                          |     |                            |  |
  |  +----------|--------------+      +-------------|------------+     +--------------|-------------+  |
  |             |                                   |                                 |                |
  |             +-----------------------------------|---------------------------------+                |
  |                                                 v                                                  |
  |                                 +-------------------------------+                                  |
  |                                 |   EKS Control Plane (ENI)     |                                  |
  |                                 |   Private Endpoint (Port 443) |                                  |
  |                                 +-------------------------------+                                  |
  +----------------------------------------------------------------------------------------------------+
                                                    ^
                                                    | Encrypted SSH Port Forward (6443 -> 443)
                                                    | OR Direct Bastion SSH Session
                                          +-----------------+
                                          | Bastion Jumpbox |
                                          +-----------------+
                                                    ^
                                                    | IAM Credentials + SSH Key
                                          +-----------------+
                                          | Developer Local |
                                          | Laptop Terminal |
                                          +-----------------+
```

### Options Overview

| Criteria | Option A: Bastion SSH Port-Forwarding (Implemented) | Option B: AWS Systems Manager (SSM) Session Manager | Option C: AWS Client VPN | Option D: EC2 Instance Connect Endpoint (EICE) |
|---|---|---|---|---|
| **Public IP Required** | Yes (Bastion only; EKS nodes remain private) | No (Private subnet) | Yes (Elastic IP for VPN) | No (AWS-managed VPC Endpoint) |
| **Inbound Open Ports** | Port 22 (SSH) | **0 Inbound Open Ports** | Port 443 / UDP 1194 | 0 Inbound Open Ports |
| **Client Software** | Standard OpenSSH client | AWS CLI + Session Manager Plugin | OpenVPN Client | AWS CLI v2 |
| **Monthly Cost** | Minimal (~$10/mo for t3.micro + NAT) | Minimal (~$10/mo for t3.micro + NAT) | High (~$110+/mo base idle cost) | Low (Hourly VPC endpoint charge) |
| **Developer Experience** | Simple: `ssh -N -L 6443:...` | Requires AWS CLI plugin | Seamless (full IP routing) | TCP tunnel via AWS CLI |
| **Local kubectl Support** | Yes (via `localhost:6443`) | Yes (via SSM port forwarding) | Yes (native DNS) | Yes (via local socket proxy) |

---

### Detailed Pros & Cons: Connectivity

#### Option A: Bastion SSH Port-Forwarding Tunnel (Implemented)
* **How it works**: A lightweight EC2 instance sits in the public subnet. The user initiates an SSH port-forwarding tunnel (`ssh -i bastion-key.pem -N -L 6443:<cluster-endpoint>:443 ec2-user@<bastion_ip>`). Local `kubectl` commands communicate through `localhost:6443` over encrypted SSH directly to the private EKS ENI.
* **Pros**:
  - **No proprietary client plugins**: Works natively out-of-the-box on Windows PowerShell, macOS, and Linux using built-in OpenSSH.
  - **High Performance**: Direct TCP tunnel without third-party agent latency.
  - **Dual Use**: Allows both local laptop `kubectl` workflows and jumpbox interactive administration.
* **Cons**:
  - Requires Bastion to have an open port 22 (restricted by security group).

#### Option B: AWS Systems Manager (SSM) Session Manager
* **How it works**: Bastion resides in a private subnet with SSM Agent. Connections are established over outbound HTTPS via AWS SSM service.
* **Pros**:
  - Zero open inbound ports.
  - Session logs streamable to AWS CloudWatch and S3.
* **Cons**:
  - Developers must install the AWS CLI `session-manager-plugin`.
  - Tunnel setup commands are longer and more complex.

#### Option C: AWS Client VPN
* **How it works**: Managed OpenVPN gateway associated with private VPC subnets.
* **Pros**:
  - Completely transparent to developers: no port forwards required.
* **Cons**:
  - Prohibitive idle cost (~$110-$150/month base cost).
  - Requires maintaining PKI client certificates or enterprise SAML identity providers.

---

## 4. Pillar 3: Namespace Multi-Tenancy & Authorization

### The 4-Tier Security Matrix

```
  ┌─────────────────┬─────────────────┬──────────────────────┬────────────────────────────────────────┐
  │ IAM User        │ Kubernetes Group│ Target Namespace     │ Permissions Enforced                   │
  ├─────────────────┼─────────────────┼──────────────────────┼────────────────────────────────────────┤
  │ eks-developer   │ dev-developers  │ dev                  │ CRUD on Pods, Deployments, Services,   │
  │                 │                 │                      │ ConfigMaps, Jobs. NO Secrets.          │
  ├─────────────────┼─────────────────┼──────────────────────┼────────────────────────────────────────┤
  │ eks-qa          │ qa-developers   │ qa                   │ CRUD on QA Workloads. NO Secrets.      │
  │                 │                 │                      │ Cannot access 'dev' or 'production'.   │
  ├─────────────────┼─────────────────┼──────────────────────┼────────────────────────────────────────┤
  │ eks-viewer      │ dev-viewers     │ dev                  │ Read-Only (get, list, watch) on Pods,  │
  │                 │                 │                      │ Deployments, Services. NO Secrets.     │
  ├─────────────────┼─────────────────┼──────────────────────┼────────────────────────────────────────┤
  │ eks-admin       │ eks-admins      │ Cluster-wide (All)   │ Full cluster-admin privileges.         │
  └─────────────────┴─────────────────┴──────────────────────┴────────────────────────────────────────┘
```

### Key Security Decisions
1. **Namespace Isolation**: `Role` and `RoleBinding` are strictly scoped to individual namespaces. A user bound to `dev` receives `403 Forbidden` when attempting to list or modify resources in `qa` or `production`.
2. **Secrets Protection**: Developers and Viewers are explicitly restricted from the `secrets` API resource. Only cluster administrators can view or edit Kubernetes secrets.
3. **Production Protection**: The `production` namespace has zero bindings to developer, QA, or viewer groups, completely preventing accidental or unauthorized deployments to production workloads.

---

## 5. Architectural Recommendation

For teams requiring **fine-grained security boundaries**, **predictable least-privilege enforcement**, and **zero external software dependencies**, **Architecture 1 (AWS IAM Users + EKS Access Entries + Pure Kubernetes RBAC)** paired with **Bastion SSH Port-Forwarding** provides the optimal balance of:
- **Maximum security**: 100% private cluster endpoint with strict namespace RBAC.
- **Minimal cost**: Uses lightweight infrastructure with no idle enterprise VPN charges.
- **Operational simplicity**: Pure Infrastructure as Code managed entirely via Terraform and Git.
