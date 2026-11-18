variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of Availability Zones"
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for resource tagging)"
  type        = string
}

