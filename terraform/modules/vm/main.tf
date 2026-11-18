# --- Amazon Linux 2023 AMI ---
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- SSH Key Pair Logic (Use existing key if provided, otherwise auto-generate) ---
locals {
  has_pubkey_file      = fileexists("${path.root}/bastion-key.pub") || fileexists("${path.root}/../bastion-key.pub")
  pubkey_file_content  = fileexists("${path.root}/bastion-key.pub") ? file("${path.root}/bastion-key.pub") : (fileexists("${path.root}/../bastion-key.pub") ? file("${path.root}/../bastion-key.pub") : "")
  effective_public_key = var.bastion_public_key != "" ? var.bastion_public_key : local.pubkey_file_content
  create_new_key       = var.bastion_key_name == "" && local.effective_public_key == ""
}

# Auto-generate RSA key pair ONLY if no custom key is provided
resource "tls_private_key" "ssh" {
  count     = local.create_new_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload public key to AWS EC2 (if not using an existing AWS key pair name)
resource "aws_key_pair" "bastion" {
  count      = var.bastion_key_name == "" ? 1 : 0
  key_name   = "${var.cluster_name}-bastion-key"
  public_key = local.create_new_key ? tls_private_key.ssh[0].public_key_openssh : local.effective_public_key
}

# Save generated private key to bastion-key.pem ONLY when newly generated
resource "local_file" "ssh_key_pem" {
  count           = local.create_new_key ? 1 : 0
  content         = tls_private_key.ssh[0].private_key_pem
  filename        = "${path.root}/bastion-key.pem"
  file_permission = "0400"
}

# Save companion public key
resource "local_file" "ssh_key_pub" {
  count           = local.create_new_key ? 1 : 0
  content         = tls_private_key.ssh[0].public_key_openssh
  filename        = "${path.root}/bastion-key.pub"
  file_permission = "0644"
}

# --- Bastion Security Group ---
resource "aws_security_group" "bastion" {
  name        = "${var.cluster_name}-bastion-sg"
  description = "Security group for Bastion jumpbox"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-bastion-sg"
  }
}

# --- Bastion IAM Role & Profile ---
resource "aws_iam_role" "bastion" {
  name = "${var.cluster_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "bastion_eks_describe" {
  name = "${var.cluster_name}-bastion-eks-describe"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster", "eks:ListClusters"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_eks_describe" {
  role       = aws_iam_role.bastion.name
  policy_arn = aws_iam_policy.bastion_eks_describe.arn
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.cluster_name}-bastion-profile"
  role = aws_iam_role.bastion.name
}

# --- Bastion EC2 Instance (Public Subnet with Public IP) ---
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  associate_public_ip_address = true
  key_name                    = var.bastion_key_name != "" ? var.bastion_key_name : aws_key_pair.bastion[0].key_name
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  vpc_security_group_ids      = [aws_security_group.bastion.id]

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user-data.sh", {
    aws_region   = var.aws_region
    cluster_name = var.cluster_name
  })

  tags = {
    Name = "${var.cluster_name}-bastion"
  }
}

