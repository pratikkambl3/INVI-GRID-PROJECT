output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Private API server endpoint of the EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "bastion_public_ip" {
  description = "Public IP of the Bastion jumpbox"
  value       = module.vm.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the Bastion"
  value       = module.vm.ssh_command
}

output "ssh_tunnel_command" {
  description = "Run this on your laptop to tunnel local kubectl to the private EKS cluster"
  value       = "ssh -i bastion-key.pem -N -L 6443:${replace(module.eks.cluster_endpoint, "https://", "")}:443 ec2-user@${module.vm.public_ip}"
}

# =====================================================================
# 3 Groups: Admin, ReadOnly, Developer
# =====================================================================

# --- 1. Admin (ClusterAdmin on Cluster Scope) ---
output "admin_username" {
  description = "IAM Username for Admin"
  value       = module.iam.admin_username
}

output "admin_arn" {
  description = "IAM User ARN for Admin"
  value       = module.iam.admin_arn
}

output "sso_admin_configured" {
  description = "Whether IAM Identity Center SSO role ARN was configured for Admin"
  value       = module.iam.sso_admin_configured
}

# --- 2. ReadOnly (ViewPolicy on Cluster Scope) ---
output "readonly_username" {
  description = "IAM Username for ReadOnly"
  value       = module.iam.readonly_username
}

output "readonly_arn" {
  description = "IAM User ARN for ReadOnly"
  value       = module.iam.readonly_arn
}

output "sso_readonly_configured" {
  description = "Whether IAM Identity Center SSO role ARN was configured for ReadOnly"
  value       = module.iam.sso_readonly_configured
}

# --- 3. Developer (ViewPolicy restricted strictly to 'dev' namespace) ---
output "developer_username" {
  description = "IAM Username for Developer"
  value       = module.iam.developer_username
}

output "developer_arn" {
  description = "IAM User ARN for Developer"
  value       = module.iam.developer_arn
}

output "sso_developer_configured" {
  description = "Whether IAM Identity Center SSO role ARN was configured for Developer"
  value       = module.iam.sso_developer_configured
}
