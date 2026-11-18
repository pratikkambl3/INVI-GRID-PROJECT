variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the Bastion will reside"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for the Bastion"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the Bastion VM"
  type        = string
  default     = "t3.medium"
}

variable "bastion_key_name" {
  description = "Name of an existing AWS Key Pair. If provided, skips key generation."
  type        = string
  default     = ""
}

variable "bastion_public_key" {
  description = "Existing OpenSSH public key string. If provided, uses this instead of generating a new key."
  type        = string
  default     = ""
}

