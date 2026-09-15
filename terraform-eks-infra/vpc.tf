module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc"
  cidr = local.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"             = 1                  # Identifies subnets for load balancers
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"            # Associates with K8s cluster
    "karpenter.sh/discovery"                      = local.cluster_name # Tag for Karpenter auto-scaling discovery
  }
  
}