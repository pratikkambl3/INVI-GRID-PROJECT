output "instance_id" {
  description = "EC2 Instance ID of the Bastion"
  value       = aws_instance.bastion.id
}

output "public_ip" {
  description = "Public IP address of the Bastion"
  value       = aws_instance.bastion.public_ip
}

output "security_group_id" {
  description = "Security Group ID of the Bastion"
  value       = aws_security_group.bastion.id
}

output "role_arn" {
  description = "IAM Role ARN of the Bastion"
  value       = aws_iam_role.bastion.arn
}

output "ssh_command" {
  description = "Command to SSH directly into the Bastion"
  value       = "ssh -i bastion-key.pem ec2-user@${aws_instance.bastion.public_ip}"
}

