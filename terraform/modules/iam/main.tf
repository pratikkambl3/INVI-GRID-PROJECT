# --- Minimum IAM Policy: Describe EKS cluster for kubeconfig generation ---
resource "aws_iam_policy" "eks_describe" {
  name        = "${var.cluster_name}-user-describe-policy"
  description = "Allows IAM users to run 'aws eks update-kubeconfig'"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

# =====================================================================
# 1. Standard IAM Users (3 Groups: Admin, ReadOnly, Developer)
# =====================================================================

# --- 1. Admin (Full Cluster Administration) ---
resource "aws_iam_user" "admin" {
  name = "eks-admin"
  tags = { Role = "Admin" }
}

resource "aws_iam_user_policy_attachment" "admin" {
  user       = aws_iam_user.admin.name
  policy_arn = aws_iam_policy.eks_describe.arn
}

# --- 2. ReadOnly (Cluster-Wide Read-Only View Across All Namespaces) ---
resource "aws_iam_user" "readonly" {
  name = "eks-readonly"
  tags = { Role = "ReadOnly" }
}

resource "aws_iam_user_policy_attachment" "readonly" {
  user       = aws_iam_user.readonly.name
  policy_arn = aws_iam_policy.eks_describe.arn
}

# --- 3. Developer (Read-Only Access strictly to 'dev' Namespace) ---
resource "aws_iam_user" "developer" {
  name = "eks-developer"
  tags = { Role = "Developer" }
}

resource "aws_iam_user_policy_attachment" "developer" {
  user       = aws_iam_user.developer.name
  policy_arn = aws_iam_policy.eks_describe.arn
}

# =====================================================================
# 2. EKS Access Entries & EKS Access Policies for IAM Users
# =====================================================================

# --- Admin Access Entry & Policy (ClusterAdmin on Cluster Scope) ---
resource "aws_eks_access_entry" "admin" {
  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_user.admin.arn
  kubernetes_groups = ["eks-admins"]
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = var.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.admin.principal_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# --- ReadOnly Access Entry & Policy (ViewPolicy on Cluster Scope) ---
resource "aws_eks_access_entry" "readonly" {
  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_user.readonly.arn
  kubernetes_groups = ["cluster-viewers"]
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "readonly" {
  cluster_name  = var.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = aws_eks_access_entry.readonly.principal_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.readonly]
}

# --- Developer Access Entry & Policy (ViewPolicy restricted to 'dev' Namespace ONLY) ---
resource "aws_eks_access_entry" "developer" {
  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_user.developer.arn
  kubernetes_groups = ["dev-viewers"]
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "developer" {
  cluster_name  = var.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = aws_eks_access_entry.developer.principal_arn

  access_scope {
    type       = "namespace"
    namespaces = ["dev"]
  }

  depends_on = [aws_eks_access_entry.developer]
}

# =====================================================================
# 3. AWS IAM Identity Center (SSO) Support via EKS Access Entries
# =====================================================================

# --- SSO Admin: Full Cluster Administrator ---
resource "aws_eks_access_entry" "sso_admin" {
  count             = var.sso_admin_role_arn != "" ? 1 : 0
  cluster_name      = var.cluster_name
  principal_arn     = var.sso_admin_role_arn
  kubernetes_groups = ["eks-admins"]
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "sso_admin" {
  count         = var.sso_admin_role_arn != "" ? 1 : 0
  cluster_name  = var.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.sso_admin[0].principal_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.sso_admin]
}

# --- SSO ReadOnly: Cluster-Wide Read-Only View Across All Namespaces ---
resource "aws_eks_access_entry" "sso_readonly" {
  count             = var.sso_readonly_role_arn != "" ? 1 : 0
  cluster_name      = var.cluster_name
  principal_arn     = var.sso_readonly_role_arn
  kubernetes_groups = ["cluster-viewers"]
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "sso_readonly" {
  count         = var.sso_readonly_role_arn != "" ? 1 : 0
  cluster_name  = var.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = aws_eks_access_entry.sso_readonly[0].principal_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.sso_readonly]
}

# --- SSO Developer: Read-Only Access restricted to 'dev' Namespace ONLY ---
resource "aws_eks_access_entry" "sso_developer" {
  count             = var.sso_developer_role_arn != "" ? 1 : 0
  cluster_name      = var.cluster_name
  principal_arn     = var.sso_developer_role_arn
  kubernetes_groups = ["dev-viewers"]
  type              = "STANDARD"
}

resource "aws_eks_access_policy_association" "sso_developer" {
  count         = var.sso_developer_role_arn != "" ? 1 : 0
  cluster_name  = var.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = aws_eks_access_entry.sso_developer[0].principal_arn

  access_scope {
    type       = "namespace"
    namespaces = ["dev"]
  }

  depends_on = [aws_eks_access_entry.sso_developer]
}
