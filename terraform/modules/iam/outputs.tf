# --- 1. Admin ---
output "admin_username" {
  value = aws_iam_user.admin.name
}

output "admin_arn" {
  value = aws_iam_user.admin.arn
}

# --- 2. ReadOnly ---
output "readonly_username" {
  value = aws_iam_user.readonly.name
}

output "readonly_arn" {
  value = aws_iam_user.readonly.arn
}

# --- 3. Developer ---
output "developer_username" {
  value = aws_iam_user.developer.name
}

output "developer_arn" {
  value = aws_iam_user.developer.arn
}

# --- SSO Status Outputs ---
output "sso_admin_configured" {
  value = var.sso_admin_role_arn != ""
}

output "sso_readonly_configured" {
  value = var.sso_readonly_role_arn != ""
}

output "sso_developer_configured" {
  value = var.sso_developer_role_arn != ""
}
