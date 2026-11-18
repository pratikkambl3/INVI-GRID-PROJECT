# --- 1. VPC Module ---
module "vpc" {
  source             = "./modules/vpc"
  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

# --- 2. Bastion VM Module (Secure Gateway to Private Cluster) ---
module "vm" {
  source           = "./modules/vm"
  cluster_name     = var.cluster_name
  vpc_id           = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_ids[0]
  aws_region       = var.aws_region
}

# --- 3. EKS Cluster Module (Strictly 100% Private Endpoint) ---
module "eks" {
  source                    = "./modules/eks"
  cluster_name              = var.cluster_name
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  bastion_security_group_id = module.vm.security_group_id
}

# --- 4. IAM & EKS Access Module (3 Groups: Admin, ReadOnly, Developer) ---
module "iam" {
  source                 = "./modules/iam"
  cluster_name           = module.eks.cluster_name
  sso_admin_role_arn     = var.sso_admin_role_arn
  sso_readonly_role_arn  = var.sso_readonly_role_arn
  sso_developer_role_arn = var.sso_developer_role_arn

  depends_on = [module.eks]
}
