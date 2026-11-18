variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "invigrid-eks"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

# --- AWS IAM Identity Center (SSO) Role ARNs ---
variable "sso_admin_role_arn" {
  description = "IAM Role ARN created by AWS IAM Identity Center for EKS Admin (e.g. AWSReservedSSO_EKS-Admin_*)"
  type        = string
  default     = ""
}

variable "sso_readonly_role_arn" {
  description = "IAM Role ARN created by AWS IAM Identity Center for EKS ReadOnly (e.g. AWSReservedSSO_EKS-ReadOnly_*)"
  type        = string
  default     = ""
}

variable "sso_developer_role_arn" {
  description = "IAM Role ARN created by AWS IAM Identity Center for EKS Developer (e.g. AWSReservedSSO_EKS-Developer_*)"
  type        = string
  default     = ""
}
