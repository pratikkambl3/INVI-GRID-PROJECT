variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "sso_admin_role_arn" {
  description = "IAM Role ARN created by AWS IAM Identity Center for EKS Admin (AWSReservedSSO_EKS-Admin_*)"
  type        = string
  default     = ""
}

variable "sso_readonly_role_arn" {
  description = "IAM Role ARN created by AWS IAM Identity Center for EKS ReadOnly (AWSReservedSSO_EKS-ReadOnly_*)"
  type        = string
  default     = ""
}

variable "sso_developer_role_arn" {
  description = "IAM Role ARN created by AWS IAM Identity Center for EKS Developer (AWSReservedSSO_EKS-Developer_*)"
  type        = string
  default     = ""
}
